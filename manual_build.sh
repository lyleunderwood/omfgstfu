#!/bin/bash
coffee -c -j lib/client/js/client.js \
  src/client/node.coffee  \
  src/client/media.coffee \
  src/client/media/*.coffee \
  src/client/app.coffee \
  src/client/filter_pane.coffee \
  src/client/upload.coffee \
  src/client/entry_form.coffee \
  src/client/message_list.coffee \
  src/client/message.coffee && \
  \
./node_modules/.bin/browserify lib/client/js/client.js -o lib/client/js/bundle.js && \
./node_modules/.bin/uglifyjs lib/client/js/bundle.js >lib/client/js/_bundle.js &&\
mv lib/client/js/_bundle.js lib/client/js/bundle.js &&\
\
node lib/server/server.js