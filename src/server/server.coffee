connect = require 'connect'
gzip = require 'gzippo'
sio = require 'socket.io'
Message = require('./message').Message
FileReceiver = require './file_receiver'
util = require 'util'
fs = require 'fs'

token_to_socket = {}

pruning = false

upload_middleware = (req, res, next) ->
  if req.url is '/upload' && req.method.toLowerCase() is 'post'
    receiver = new FileReceiver(req)

    socket = token_to_socket[receiver.get_token()]
    receiver.on 'end', (image_url) ->
      res.writeHead 200, 'Content-Type': 'application/json'
      res.write JSON.stringify
        path: image_url

      res.end()

    receiver.on 'error', (error) ->
      res.writeHead error.code || 406, 'Content-Type': 'application/json'
      res.write JSON.stringify error

  else
    next()

two_days = 2*24*60*60*1000

app = connect()
  #.use(gzip.compress())
  .use(connect.logger 'dev')
  .use(upload_middleware)
  .use(connect.static __dirname + '/../client', maxAge: two_days)
  .listen (process.env['app_port'] || 3001), ->

    io = sio.listen this

    io.sockets.on 'connection', (socket) ->

      socket.on 'get_messages', (params) ->
        Message.all params, (error, messages) ->
          socket.emit 'messages', messages

      socket.on 'message', (data) ->
        data.author_ip = socket.handshake.address.address

        # this regex was originally /^\s*$/ but for some reason that would match
        # any string which contained "true" anywhere in it. it really didn't
        # make any sense, and this doesn't seem to happen in most regexp
        # implementations. i assume it's some kinda node bug.
        return if !data.content? || (data.content.match(/^[ \t\n]*$/) != null)

        message = new Message data

        message.save (error, id) ->
          console.log "New message ID: #{id}"

          process.nextTick ->
            return null if pruning
            pruning = true

            Message.prune (error, images_to_delete) ->
              pruning = false

              return console.log 'failed to prune', error if error

              return null unless images_to_delete

              for image in images_to_delete
                FileReceiver.delete image, (error, result) ->
                  console.log "failed to delete #{image}, #{error.statusCode}" if error
                  console.log 'successfully deleted', image

        io.sockets.emit 'messages', [message]

      socket.on 'create_session', (data, cb) ->
        token = data.token || create_session_token()
        cb
          token: token
          color: data.color || create_color()

        token_to_socket[token] = socket

        socket.set 'options', data

        connection_message = new Message
          content:      (data.name || 'Anonymous') + " connected."
          author_name:  "Server"
          server_event: true

        socket.broadcast.emit 'messages', [connection_message]

        connection_message.save ->

      socket.on 'disconnect', ->
        socket.get 'options', (error, data) ->
          name = if data? and data.name? then data.name else 'Anonymous'

          disconnect_message = new Message
            content: "#{name} disconnected."
            author_name: 'Server'
            server_event: true

          socket.broadcast.emit 'messages', [disconnect_message]

          disconnect_message.save ->

create_color = ->
  parts = []
  for i in [0..2]
    parts.push Math.round(Math.random() * 155) + 100

  parts

create_session_token = ->
  chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  ret = ''

  for bit in [24...0]
    ret += chars[0x3F & (Math.floor(Math.random() * 0x100000000))]

  ret
