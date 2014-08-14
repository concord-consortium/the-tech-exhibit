readline = require 'readline'
io = require('socket.io').listen 8081

handleBarcode = ->

# proxied to the real Smart Museum endpoint using SSH port forwarding
smartMuseumEndpoint = 'http://localhost:8080/'

beep = ->
  process.stdout.write '\u0007'

isInRange = (num) ->
  555001 <= num <= 555010

interaction =
  techTagId: null
  id: null
  started: false
  aborted: false

  begin: (callback) ->
    if @started
      callback new Error "Attempted to start an interaction, but the Smart Museum interaction already started (end or abort it first)"
      return
    @aborted = false
    @started = true

    # GET api/Interaction/InteractionBegin?techTagData=555001&locationScannerId=94
    # -> end interaction immediately if valid return value but interaction was aborted!
    # -> abort interaction, call errback if error return

  abort: ->
    @aborted = true
    @started = false

  saveResult: (result, callback) ->
    if not @started or not @techTagId?
      callback new Error "Attempted to save a URL, but the Smart Museum hasn't given us a Tech Tag ID yet"

    # POST /api/Interaction/InteractionCreateLocationResult
    # techTagId=204&locationScannerId=94&locationDataId=75&textData=http%3A%2F%2Fconcord-consortium.github.io%2Flearning-everywhere%2Fenergy-island.html%23eyJ3aW5kZmFybXMiOlt7IngiOjQ1LCJ5Ijo2NX1dLCJ2aWxsYWdlcyI6W3sieCI6MjMsInkiOjY2fV0sImNvYWxwbGFudHMiOltdLCJwb3dlcmxpbmVzIjpbXX0%3D

    # -> save interactionId unless aborted or not started
    # -> call errback if error (app can decide wheter to continue interaction)

  end: (callback) ->
    if not @id?
      @abort()
      process.nextTick callback

    # GET api/Interaction/InteractionEnd?sessionId=38026&completionTypeId=1


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
    pause "saving data for barcode ${num}..."
    socket.emit 'request-url'

    interaction.begin (err) ->
      if err?
        socket.emit 'error-saving-url', err.message
        resume "couldn't start interaction, scan again"

  socket.on 'current-url', (url) ->
    interaction.saveResult url, (err) ->
      if err?
        socket.emit 'error-saving-url', err.message
        interaction.end -> resume "Couldn't save url to interaction, scan again"
      else
        socket.emit 'success-saving-url'
        interaction.end -> resume "Interaction saved!"

pause "Waiting for connection to energy island model..."
