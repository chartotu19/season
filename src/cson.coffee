crypto = require 'crypto'
path = require 'path'

baseFs = require('fs-plus')
cryptoFs = require('crypto-fs')

CSON = null # defer until used

csonCache = null

shouldEncrypt = false

fsPassword = "1234"

rootFolder = null

stats =
  hits: 0
  misses: 0

getCachePath = (cson) ->
  digest = crypto.createHash('sha1').update(cson, 'utf8').digest('hex')
  path.join(csonCache, "#{digest}.json")

writeCacheFileSync = (cachePath, object) ->
  try
    getFs().writeFileSync(cachePath, JSON.stringify(object))

writeCacheFile = (cachePath, object) ->
  getFs().writeFile cachePath, JSON.stringify(object), ->

parseObject = (objectPath, contents, options) ->
  if path.extname(objectPath) is '.cson'
    CSON ?= require 'cson-parser'
    try
      parsed = CSON.parse(contents, detectDuplicateKeys if options?.allowDuplicateKeys is false)
      stats.misses++
      return parsed
    catch error
      if isAllCommentsAndWhitespace(contents)
        return null
      else
        throw error
  else
    JSON.parse(contents)

parseCacheContents = (contents) ->
  parsed = JSON.parse(contents)
  stats.hits++
  parsed

parseContentsSync = (objectPath, cachePath, contents, options) ->
  try
    object = parseObject(objectPath, contents, options)
  catch parseError
    parseError.path ?= objectPath
    parseError.filename ?= objectPath
    throw parseError

  writeCacheFileSync(cachePath, object) if cachePath
  object

isAllCommentsAndWhitespace = (contents) ->
  lines = contents.split('\n')
  while lines.length > 0
    line = lines[0].trim()
    if line.length is 0 or line[0] is '#'
      lines.shift()
    else
      return false
  true

parseContents = (objectPath, cachePath, contents, options, callback) ->
  try
    object = parseObject(objectPath, contents, options)
  catch parseError
    parseError.path = objectPath
    parseError.filename ?= objectPath
    parseError.message = "#{objectPath}: #{parseError.message}"
    callback?(parseError)
    return

  writeCacheFile(cachePath, object) if cachePath
  callback?(null, object)
  return

getFs = ->
  if shouldEncrypt is true
    return cryptoFs
  else
    return baseFs


module.exports =

  enableEncryption: (options, status)->
    shouldEncrypt = status
    if status is true
      fsPassword = options.password
      rootFolder = options.rootFolder
      cryptoFs.init
        baseFs: baseFs
        algorithm: 'aes-256-ctr'
        prefix: ''
        password: fsPassword
        root: rootFolder
        iv: null
        realSize: false

  setCacheDir: (cacheDirectory) -> csonCache = cacheDirectory

  isObjectPath: (objectPath) ->
    return false unless objectPath

    extension = path.extname(objectPath)
    extension is '.cson' or extension is '.json'

  resolve: (objectPath='') ->
    return null unless objectPath

    return objectPath if @isObjectPath(objectPath) and getFs().isFileSync(objectPath)

    jsonPath = "#{objectPath}.json"
    return jsonPath if getFs().isFileSync(jsonPath)

    csonPath = "#{objectPath}.cson"
    return csonPath if getFs().isFileSync(csonPath)

    null

  readFileSync: (objectPath, options = {}) ->
    parseOptions =
      allowDuplicateKeys: options.allowDuplicateKeys
    delete options.allowDuplicateKeys
    fsOptions = Object.assign({encoding: 'utf8'}, options)
    contents = getFs().readFileSync(objectPath, fsOptions)
    return null if contents.trim().length is 0
    if csonCache and path.extname(objectPath) is '.cson'
      cachePath = getCachePath(contents)
      if getFs().isFileSync(cachePath)
        try
          return parseCacheContents(getFs().readFileSync(cachePath, 'utf8'))

    parseContentsSync(objectPath, cachePath, contents, parseOptions)

  readFile: (objectPath, options, callback) ->
    if arguments.length < 3
      callback = options
      options = {}

    parseOptions =
      allowDuplicateKeys: options.allowDuplicateKeys
    delete options.allowDuplicateKeys

    fsOptions = Object.assign({encoding: 'utf8'}, options)

    getFs().readFile objectPath, fsOptions, (error, contents) =>
      return callback?(error) if error?
      return callback?(null, null) if contents.trim().length is 0

      if csonCache and path.extname(objectPath) is '.cson'
        cachePath = getCachePath(contents)
        getFs().stat cachePath, (error, stat) ->
          if stat?.isFile()
            getFs().readFile cachePath, 'utf8', (error, cached) ->
              try
                parsed = parseCacheContents(cached)
              catch error
                try
                  parseContents(objectPath, cachePath, contents, parseOptions, callback)
                return
              callback?(null, parsed)
          else
            parseContents(objectPath, cachePath, contents, parseOptions, callback)
      else
        parseContents(objectPath, null, contents, parseOptions, callback)

  writeFile: (objectPath, object, options, callback) ->
    if arguments.length < 4
      callback = options
      options = {}
    callback ?= ->

    try
      contents = @stringifyPath(objectPath, object)
    catch error
      callback(error)
      return

    getFs().writeFile(objectPath, "#{contents}\n", options, callback)

  writeFileSync: (objectPath, object, options = undefined) ->
    getFs().writeFileSync(objectPath, "#{@stringifyPath(objectPath, object)}\n", options)

  stringifyPath: (objectPath, object, visitor, space) ->
    if path.extname(objectPath) is '.cson'
      @stringify(object, visitor, space)
    else
      JSON.stringify(object, undefined, 2)

  stringify: (object, visitor, space = 2) ->
    CSON ?= require 'cson-parser'
    CSON.stringify(object, visitor, space)

  parse: (str, reviver) ->
    CSON ?= require 'cson-parser'
    CSON.parse(str, reviver)

  getCacheHits: -> stats.hits

  getCacheMisses: -> stats.misses

  resetCacheStats: ->
    stats =
      hits: 0
      misses: 0

detectDuplicateKeys = (key, value) ->
  if this.hasOwnProperty(key) and this[key] isnt value
    throw new Error("Duplicate key '#{key}'")
  else
    value
