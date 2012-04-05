express = require 'express'
pg = require 'pg'
env = process.env
app = express.createServer()

INSERTION_INTERVAL_SEC = 5
HISTORY_SIZE = 30
HASH_EXAMPLE1 = "W5xfIa45"
HASH_EXAMPLE2 = "X1PZTLm"
MAX_URL_LENGTH = 3000

app.configure ->
  app.set('views', __dirname + '/views')
  app.set('view engine', 'jade')
  app.set('view options', layout: false)
  app.use(express.favicon())
  app.use(express.logger())
  app.use(express.limit('500kb'))
  app.use(express.bodyParser())
  app.use(express.cookieParser())
  app.use(express.session(secret: env.SECRET_KEY))
  app.use(express.methodOverride())
  app.use(app.router)
  app.use(express.static(__dirname + '/public'))
  app.use(express.static(__dirname + '/kickstart'))

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
    res.send('Not found')

class HTTPError extends Error
  constructor: (@status, @message) ->

class NotInNetworkError extends HTTPError
  constructor: (@userIp, @ipAddress, @prefixMask) ->
    super(403)

app.use (err, req, res, next) ->
  res.status(err.status || 500)
  if err instanceof NotInNetworkError
    res.render('not-in-network', err)
  else if req.accepts 'json'
    res.send(error: err.message)
  else
    res.render('error', error: err)

# Routes

connectDb = (req, res, next) ->
  pg.connect env.DATABASE_URL, (err, client) ->
    req.dbClient = client
    if err
      next(new Error(err))
    else next()

generateRandomString = (size, randomSize) ->
  allChar = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
  (allChar.charAt(Math.floor Math.random() * allChar.length) \
    for i in [1..size + Math.random() * randomSize]).join('')

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


app.get '/', (req, res) ->
  
  req.session.csrfToken =
    generateRandomString 5, 2 unless req.session.csrfToken
  
  # req.cookies.url_history ==
  # '<shortUrl>:<longUrl>:<ipAddress>:<prefixMask>;<shortURL>...'
  historiesStr = req.cookies?.url_history?.split(/;/) ? []
  histories = ((decodeURIComponent(elm) for elm in str.split /:/) \
    for str in historiesStr)
  
  res.render('index.jade',
    histories: histories
    token: req.session.csrfToken
    insertionIntervalSec: INSERTION_INTERVAL_SEC
    historySize: HISTORY_SIZE
    env: env
    hashExample:
      if isAcceptableIp(req.connection.remoteAddress, '0.0.0.0', 1)
        HASH_EXAMPLE1
      else
        HASH_EXAMPLE2)

getRedirection = (callback) ->
  (req, res, next) ->
    hash = req.params.hash
    unless /[0-9a-zA-Z]+/.test(hash)
      next()
      return
    req.dbClient.query("SELECT * from urls
        where hash = $1 limit 1", [hash], (err, result) ->
      if err
        next(new Error(err))
      else if result.rows.length == 0
        next()
      else
        row = result.rows[0]
        if isAcceptableIp(req.connection.remoteAddress,
            row.ip_address, row.network_prefix)
          callback(res, req, row, result, next)
        else
          next(new NotInNetworkError(req.connection.remoteAddress,
              row.ip_address, row.network_prefix))
    )

app.get '/r/:hash', connectDb, getRedirection (res, req, data) ->
  res.redirect(data.long_url)

app.get '/c/:hash', connectDb, getRedirection (res, req, data) ->
  res.render('confirm-url',
    data: data,
    userIp: req.connection.remoteAddress
  )

checkSession = (req, res, next) ->
  token = req.param('token', '')
  unless req.session.csrfToken
    next(new HTTPError(400, 'No access token'))
  else if token isnt req.session.csrfToken
    next(new HTTPError(400, 'Invalid access token'))
  else if req.session.lastInserted and \
      new Date().getTime() - req.session.lastInserted \
        < INSERTION_INTERVAL_SEC * 1000
    next(new HTTPError(503, 'Accessed too tightly'))
  else
    next()

validateRedrection = (req, res, next) ->
  {longUrl, ipAddress, prefixMask} = req.postingData =
    longUrl: req.param('url', '')
    ipAddress: req.param('ip-address', '')
    prefixMask: +req.param('prefix-mask', 0)
  
  isValid = /^https?:\/\//.test(longUrl) \
      and longUrl.length <= MAX_URL_LENGTH \
      and isValidSplitIp(ipAddress.split /\./) and 0 < prefixMask <= 32
  
  if isValid then next()
  else next(new HTTPError(400, 'Invalid data format'))

app.post '/redirects/new', checkSession, validateRedrection, \
    connectDb, (req, res, next) ->
  {longUrl, ipAddress, prefixMask} = req.postingData
  tryInsert = (depth) ->
    hash = generateRandomString 6.9, 2.1
    req.dbClient.query('INSERT INTO urls(
        long_url, hash, ip_address, network_prefix)
        VALUES($1, $2, $3, $4)', \
        [longUrl, hash, ipAddress, prefixMask], (err, result) ->
          if err
            console.log err
            if depth > 0 and err.code is 23505 # UNIQUE VIOLATION
              tryInsert(depth - 1) # re-create hash and retry
            else
              next(new Error(err))
          else
            if req.accepts 'json'
              res.send(
                shortUrl: "#{env.URL}/r/#{hash}"
                confirmingUrl: "#{env.URL}/c/#{hash}"
              )
            else
              res.send "created at: #{env.URL}/r/#{hash}"
            req.session.lastInserted = new Date().getTime()
    )
  tryInsert(10)

# db

( ->
  req = {}
  connectDb req, null, (err) ->
    require('./db-initializer').init(req.dbClient,
      HASH_EXAMPLE1, HASH_EXAMPLE2) unless err
)()

unless module.parent
  app.listen(env.PORT)
  console.log('Express started on port 3000')
