express = require 'express'
pg = require 'pg'
async = require 'async'
env = process.env
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
  res.render('error', error: err)

# Routes

connectDb = (req, res, next) ->
  pg.connect env.DATABASE_URL, (err, client) ->
    req.dbClient = client
    if err
      next(new Error(err))
    else next()

app.get '/', (req, res) ->
  res.render('index.jade')

app.get '/404', (req, res, next) ->
  next()

isValidSplitIp = (sections) ->
    return (sections.length == 4 and
        sections.every (v) -> /^\d+$/.test(v) and 0 <= v < 256)

isAcceptableIp = (userIp, requiredIp, prefixMask) ->
  addresses = []
  for ip, i in [userIp, requiredIp]
    sections = ip.split(/\./)
    return false unless isValidSplitIp(sections)
    addresses[i] = (sections.reduce ((k, x) -> k * 256 + +x), 0) \
        & -(1 << 32 - prefixMask)
    
  return addresses[0] == addresses[1]

getRedirection = (callback) ->
  (req, res, next) ->
    hash = req.params.hash
    unless /[0-9a-zA-Z]+/.test(hash)
      next()
      return
    req.dbClient.query("SELECT * from urls where hash = $1 limit 1", [hash], (err, result) ->
      if err
        next(new Error(err))
      else if result.rowCount == 0
        next()
      else
        row = result.rows[0]
        if isAcceptableIp req.connection.remoteAddress, row.ip_address, row.prefix
          callback(res, req, row.long_url, result, next)
        else
          next(new Error('Not in range!'))
    )

app.get '/r/:hash', connectDb, getRedirection (res, req, url) ->
  res.redirect(url)

app.get '/c/:hash', connectDb, getRedirection (res, req, url) ->
  res.render('confirm-url', url: url)


validateRedrection = (req, res, next) ->
  {longUrl, ipAddress, prefixMask} = req.postingData =
    longUrl: req.param('url', '')
    ipAddress: req.param('ip-address', '')
    prefixMask: +req.param('prefix-mask', 0)
  
  isValid = /^https?:\/\//.test(longUrl) \
      and isValidSplitIp(ipAddress.split /\./) and 0 < prefixMask <= 32
  
  if isValid then next()
  else next(new Error('invalid!!'))

app.post '/redirects/new', validateRedrection, connectDb, (req, res, next) ->
  {longUrl, ipAddress, prefixMask} = req.postingData
  allChar = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
  tryInsert = () ->
    hash = (allChar.charAt(Math.floor Math.random() * allChar.length) \
        for i in [1..6.9 + Math.random() * 2.1]).join('')
    req.dbClient.query('INSERT INTO urls(
        long_url, hash, ip_address, network_prefix) VALUES($1, $2, $3, $4)',
        [longUrl, hash, ipAddress, prefixMask], (err, result) ->
          if err
            console.log err
            if err.code is 23505 # UNIQUE VIOLATION
              tryInsert() # re-create hash and retry
            else
              next(new Error(err))
          else
            res.send "created at: #{env.URL}/r/#{hash}"
    )
  tryInsert()

app.get '/403', (req, res, next) ->
  err = new Error('not allowed!')
  err.status = 403
  next(err)

app.get '/500', (req, res, next) ->
  next(new Error('keyboard cat!'))

# db

( ->
  req = {}
  connectDb req, null, (err) ->
    require('./db-initializer').init(req.dbClient) unless err
)()

unless module.parent
  app.listen(env.PORT)
  console.log('Express started on port 3000')