async = require 'async'

requestFactory = require LIB_DIR + '/requestfactory.js'
request = requestFactory()

storage = require(LIB_DIR + '/storage.js')('faction')

plugins = require('require-all')
    dirname: PLUGINS_DIR + '/faction'
    filter : /(.+)\.js$/,

pluginList = []
pluginList.push plugin for pname, plugin of plugins

FactionListener = GLOBAL.FactionListener =
    
    init: (callback) ->

        storage.fetch
            lastParsedGuid: null
            lastParsedTime: null
        , ->
            async.eachSeries pluginList, (plugin, callback) ->
                if plugin.init?
                    plugin.init callback
                else
                    callback()
            , callback

    start: ->

        Bot.exec '--faction', Config.Faction.MaxTimeout, (err) ->
            
            if err
                logger.error '[Faction] Error: %s', err.message

            parseData ->
                setTimeout FactionListener.start, Config.Faction.FetchInterval

parseData = (callback) ->

    storage.lastParsedTime = Date.now() - Config.Faction.MaxParseTimespan if storage.lastParsedTime is null
    
    Database.db.collection('Chat.Faction').find({time: {$gte: storage.lastParsedTime}}).sort {time: 1}, (err, cursor) ->

        flag = false

        next = ->

            cursor.nextObject p

        finish = ->

            callback && callback()

        p = (err, item) ->

            return finish() if item is null

            flag = true if storage.lastParsedGuid is null
            
            if storage.lastParsedGuid isnt null and flag is false
                if item._id is storage.lastParsedGuid
                    flag = true

                return next()
            
            storage.lastParsedTime = item.time
            storage.lastParsedGuid = item._id
            storage.save()

            # call test() on all plugins
            tests = []

            for plugin in pluginList
                if typeof plugin.test is 'function'
                    testResult = plugin.test item

                    if typeof testResult is 'boolean'
                        testResult =
                            ok:         testResult
                            priority:   0
                    else if typeof testResult is 'number'
                        testResult =
                            ok:         true
                            priority:   testResult

                    if testResult.ok
                        tests.push
                            priority: testResult.priority
                            plugin:   plugin

            return next() if tests.length is 0

            # sort by priority DESC
            tests.sort (a, b) ->
                b.priority - a.priority

            # call process() on these plugins
            async.eachSeries tests, (t, callback) ->

                t.plugin.process item, (error) ->

                    # if error: goto next plugin
                    if error
                        callback() 
                    else
                        callback 'stop'

            next()

        next()

FactionUtil = GLOBAL.FactionUtil = 
    
    isCallingBot: (item) ->

        return true if /@shanghaienlbot\d*/gi.test item.text
        return true if /#bot/g.test item.text

        false

    parseCallingBody: (item) ->

        str = item.text
        str = str.replace(/@shanghaienlbot\d*/gi, '');
        str = str.replace(/#bot/g, '');
        str = str.trim()

        player = item.markup.SENDER1.plain
        player = player.substr 0, player.length - 2

        raw:    item
        body:   str
        player: player

    send: (message, completeCallback) ->

        # DEBUG
        #console.log 'send: %s', message
        #completeCallback && completeCallback()
        #return

        lat = Config.Faction.Center.Lat + Math.random() * 0.2 - 0.1
        lng = Config.Faction.Center.Lng + Math.random() * 0.2 - 0.1

        data =
            message: message.toString()
            latE6: Math.round(lat * 1e6)
            lngE6: Math.round(lng * 1e6)
            chatTab: 'faction'

        request.push

            action: 'sendPlext'
            data:   data
            onError: (err, callback) ->

                logger.error "[SendMessage] Failed to send: #{err.message}"
                callback()

            afterResponse: (callback) ->

                if data.message.length > 30
                    thMsg = data.message.substr(0, 30) + '...'
                else
                    thMsg = data.message

                logger.info "[SendMessage] Sent: #{thMsg}"

                callback()
                completeCallback && completeCallback()
