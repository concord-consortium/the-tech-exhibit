readline = require 'readline'

beep = ->
  process.stdout.write '\u0007'

isInRange = (num) ->
  555001 <= num <= 555010

rl = readline.createInterface
  input: process.stdin,
  output: process.stdout

rl.on 'line', (line) ->
  num = parseInt line, 10
  if isInRange num
    beep()
  else
    console.error "barcode is not in range"
