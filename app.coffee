express = require 'express'
pg = require 'pg'
async = require 'async'
env =
  if 'DATABASE_URL' of process.env
    process.env
  else
    require './local-env'

app = express.createServer()

app.configure ->
  app.set('views', __dirname + '/views')
  app.set('view engine', 'jade')
  app.set('view options', layout: false)
  app.use(express.favicon())
  app.use(express.logger())
  app.use(express.limit('500kb'))
  app.use(express.bodyParser())
  app.use(express.methodOverride())
  app.use(app.router)
  app.use(express.static(__dirname + '/public'))

  app.use (req, res, next) ->
    # respond with html page
    if req.accepts('html')
      res.status(404)
      res.render('404', url: req.url)
      return
  
    # respond with json
    if req.accepts('json') 
      res.send(error: 'Not found')
      return
  
    # default to plain-text. send()
    res.type('txt').send('Not found')

app.use (err, req, res, next) ->
  # we may use properties of the error object
  # here and next(err) appropriately, or if
  # we possibly recovered from the error, simply next().
  res.status(err.status || 500)
  res.render('500', error: err)

# Routes

app.get '/', (req, res) ->
  res.render('index.jade')

app.get '/404', (req, res, next) ->
  next()

app.get '/403', (req, res, next) ->
  err = new Error('not allowed!')
  err.status = 403
  next(err)

app.get '/500', (req, res, next) ->
  next(new Error('keyboard cat!'))

unless module.parent
  app.listen(env.PORT)
  console.log('Express started on port 3000')