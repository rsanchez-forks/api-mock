inheritHeaders = require './inherit-headers'
inheritParameters = require './inherit-parameters'
expandUriTemplateWithParameters = require './expand-uri-template-with-parameters'
exampleToHttpPayloadPair = require './example-to-http-payload-pair'

ut = require 'uri-template'
winston = require 'winston'

walker = (app, resourceGroups) ->

  sendResponse = (responses, needsAuthorization) ->
    (req, res) ->
      if needsAuthorization && !req.get('Authorization')
        return res.send 401

      # default response
      response = responses[Object.keys(responses)[0]]

      # try to find matching response based on PREFER header
      if 'prefer' of req.headers
        if req.headers['prefer'] of responses
          response = responses[req.headers['prefer']]
        else
          winston.warn("[#{req.url}] Preferrered response #{req.headers['prefer']} not found. Falling back to #{response.status}")

      for header, value of response.headers
        headerName = value['name']
        headerValue = value['value']
        res.setHeader headerName, headerValue
      res.setHeader 'Content-Length', Buffer.byteLength(response.body)
      res.send response.status, response.body

  responses = []

  for group in resourceGroups
    for resource in group['resources']
      for action  in resource['actions']

        # headers and parameters can be specified higher up in the ast and inherited
        action['headers'] = inheritHeaders action['headers'], resource['headers']
        action['parameters'] = inheritParameters action['parameters'], resource['parameters']

        if resource['uriTemplate']?
          # removes query parameters, and converts uri template params into what express expects
          # e.g. /templates/{templateId}/?status=good would become /templates/:templateId/
          # TODO: replate with uri template processing
          path = resource['uriTemplate'].split('{?')[0].replace(new RegExp("}","g"), "").replace(new RegExp("{","g"), ":")

          # the routes are generated
          for example in action['examples']
            payload = exampleToHttpPayloadPair example, action['headers']
            needsAuthorization = false

            for warning in payload['warnings']
              winston.warn("[#{path}] #{warning}")

            for error in payload['errors']
              winston.error("[#{path}] #{error}")

            if 'requests' of example && example.requests.length > 0
              for header in example.requests[0].headers
                if header.name == 'Authorization'
                  needsAuthorization = true

            responses.push {
              method: action.method
              path: path
              needsAuthorization: needsAuthorization
              responses: payload['pair']['responses']
            }

  #sort routes
  responses.sort (a,b) ->
    if (a.path > b.path)
       return -1
    if (a.path < b.path)
      return 1
    return 0

  for response in responses
    switch response.method
      when 'GET'
        app.get response.path, sendResponse(response.responses, response.needsAuthorization)
      when 'POST'
        app.post response.path, sendResponse(response.responses, response.needsAuthorization)
      when 'PUT'
        app.put response.path, sendResponse(response.responses, response.needsAuthorization)
      when 'DELETE'
        app.delete response.path, sendResponse(response.responses, response.needsAuthorization)
      when 'PATCH'
        app.patch response.path, sendResponse(response.responses, response.needsAuthorization)



module.exports = walker
