readline = require 'readline'
request = require 'request'
express = require 'express'

io = require('socket.io').listen 8081

# proxied to the real Smart Museum endpoint using SSH port forwarding
smartMuseumEndpoint = 'http://localhost:8082'

# ports
# 8080: server
# 8081: socket.io connection to client
# 8082: smart museum api

handleBarcode = ->

beep = ->
  process.stdout.write '\u0007'

isInRange = (num) ->
  555001 <= num <= 555010

# singleton object that keeps track of a single ongoing transaction with the Smart Museum system
makeInteraction = ->
  techTagId: null
  id: null
  started: false
  aborted: false

  begin: (num, callback) ->
    if @started
      callback new Error "Attempted to start an interaction, but the Smart Museum interaction already started (end or abort it first)"
      return
    @aborted = false
    @started = true
    url = "#{smartMuseumEndpoint}/api/Interaction/InteractionBegin?techTagData=#{num}&locationScannerId=94"
    console.log "requesting #{url}"

    request.get {url: url, json: true}, (err, response, body) =>
      console.log "got #{url}, error = #{err?}"
      if err?
        @abort()
        callback err
        return
      # if aborted, forget we asked to begin an interaction
      return if @aborted
      @techTagId = body[0].TechTagId
      @id = body[0].InteractionId
      console.log "techTagId = #{@techTagId}, interactionId=#{@id}"
      callback null

  abort: ->
    @aborted = true
    @started = false

  saveResult: (result, callback) ->
    if not @started or not @techTagId?
      callback new Error "Attempted to save a URL, but the Smart Museum hasn't given us a Tech Tag ID yet"

    url = "#{smartMuseumEndpoint}/api/Interaction/InteractionCreateLocationResult"

    console.log "posting to #{url}"

    # POST
    formData =
      techTagId: @techTagId
      locationScannerId: 94
      locationDataId: 75
      textData: result

    request.post {url: url, form: formData}, (err, response, body) =>
      console.log "posted to #{url}, error = #{err?}"

      return if not @started or @aborted

      if err?
        callback err
        return

      if typeof body is 'string'
        body = JSON.parse body

      if body.TechTagId isnt @techTagId
        callback new Error "Received results for wrong interaction"
        return

      if not body.Results?[0]?.Data
        callback new Error "URL does not appear to have been saved on Smart Museum server"
        return

      callback null

  getLastResult: (callback) ->
    url = "#{smartMuseumEndpoint}/api/Interaction/InteractionGetLocationResults?locationId=143&locationDataId=75&techTagId=#{@techTagId}&includeMediaData=false"
    request.get {url: url, json: true}, (err, response, body) ->
      if err?
        callback err
        return

      if not body[0]?.Results?[0]?.Data
        callback new Error "Couldn't get URL from Smart Museum system"
        return

      callback null, body[0].Results[0].Data


  end: (callback) ->
    if not @id?
      @abort()
      if callback? then process.nextTick callback

    url = "#{smartMuseumEndpoint}/api/Interaction/InteractionEnd?sessionId=#{@id}&completionTypeId=1"
    console.log "requesting #{url}"

    request.get {url: url}, (err, response, body) =>
      console.log "got #{url}, error = #{err?}"
      if err?
        callback? err
        @abort()
        return

      if body.Message isnt "Success"
        callback? new Error "Interaction was not ended!"
        @abort()
        return

      @aborted = false
      @started = false
      callback? null

interaction = makeInteraction()

rl = readline.createInterface
  input: process.stdin,
  output: process.stdout

rl.on 'line', (line) ->
  num = parseInt line, 10
  if isInRange num
    beep()
    handleBarcode num
  else
    console.error "barcode is not in range"

pause = (msg) ->
  rl.pause()
  if msg? then console.log msg

resume = (msg) ->
  rl.resume()
  if msg? then console.log msg

io.on 'connection', (socket) ->
  resume "Connected."

  handleBarcode = (num) ->
    pause "saving data for barcode #{num}..."

    interaction.begin num, (err) ->
      if err?
        socket.emit 'error-saving-url', err.message
        resume "couldn't start interaction, scan again"
        return
      socket.emit 'request-url'

  socket.on 'current-url', (url) ->
    console.log "got url from client: #{url}"
    interaction.saveResult url, (err) ->
      if err?
        socket.emit 'error-saving-url', err.message
        interaction.end -> resume "Couldn't save url to interaction, scan again"
      else
        socket.emit 'success-saving-url'
        interaction.end -> resume "Interaction saved!"

pause "Waiting for connection to energy island model..."


# server for getting client
app = express()

app.get '/', (req, res) ->
  res.send 'visit saved?tag=<tech tag number> to see the saved model'

app.get '/saved', (req, res) ->
  if not req.query.tag?
    res.send 'visit saved?tag=<tech tag number> to see the saved model'
    return

  tagNumber = req.query.tag

  interaction = makeInteraction()
  interaction.begin tagNumber, (err) ->
    if err?
      res.send "Couldn't talk to Smart Museum: #{err.message}"
      return
    interaction.getLastResult (err, url) ->
      if err?
        res.send "Couldn't get tag information from Smart Museum: #{err.message}"
        return
      res.redirect url
      interaction.end()

app.listen 8080
