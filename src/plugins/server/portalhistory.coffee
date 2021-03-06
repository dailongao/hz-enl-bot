moment = require 'moment'

###

下毒规则：

毒到自己阵营：
    1. [DESTROY RESONATOR] markup.PLAYER1.team == markup.PORTAL1.team

毒到对方阵营：
    1. 两次时间相邻的DESTROY RESONATOR，markup.PORTAL1.team不一致，且中间没有capture   -> 最近一次被毒
    2. 两次中最近一次不符合“毒到自己阵营”                                              -> 最近一次被毒到对方阵营

    1. 最近一次 DESTROY，较远一次 CAPTURE，markup.PORTAL1.team不一致                  -> 最近一次被毒
    2. 两次中最近一次不符合“毒到自己阵营”                                              -> 最近一次被毒到对方阵营

###

get_portal_history = (req, res) ->

    guid = req.params.guid
    minTimestampMs = parseInt(req.params.mintimestampms)

    Database.db.collection('Chat.Public').find
        'markup.PORTAL1.guid': guid
        'time':
            $gte: minTimestampMs
    .sort {time: -1}, (err, cursor) ->

        records = []

        lastDestroyEvent = null
        lastCaptureEvent = null

        impossibleEvents = {}

        next = ->

            setImmediate ->
                cursor.nextObject p

        finish = ->

            lastTime = null

            response = []

            # sort desc
            records.sort (a, b) ->

                return b.time - a.time if b.time isnt a.time
                return a.event - b.event

            # unique
            for rec in records
                response.push rec if rec.time isnt lastTime
                lastTime = rec.time

            # time str
            for rec in response
                rec.time_str = moment(rec.time).format 'LLLL' if rec.time?

            res.jsonp response

        p = (err, item) ->

            return finish() if item is null

            # flip to own faction
            
            if item.markup.TEXT1.plain is ' linked '
                if lastDestroyEvent?
                    if lastDestroyEvent.markup.PORTAL1.team is item.markup.PORTAL1.team
                        impossibleEvents[lastDestroyEvent._id] = true
                
                return next()

            if item.markup.TEXT1.plain is ' deployed an '
                if lastDestroyEvent?
                    if lastDestroyEvent.markup.PORTAL1.team is item.markup.PORTAL1.team
                        impossibleEvents[lastDestroyEvent._id] = true

                return next()
            
            if item.markup.TEXT1.plain is ' captured '
                records.push
                    time:   item.time
                    player: item.markup.PLAYER1
                    event:  'capture'
                    portal: item.markup.PORTAL1

                if lastDestroyEvent?
                    if lastDestroyEvent.markup.PORTAL1.team isnt item.markup.PORTAL1.team
                        if lastDestroyEvent.markup.PLAYER1.team isnt lastDestroyEvent.markup.PORTAL1.team and not impossibleEvents[lastDestroyEvent._id]?
                            records.push
                                time:    lastDestroyEvent.time
                                player:  lastDestroyEvent.markup.PLAYER1
                                event:   'flip'
                                event2:  if lastDestroyEvent.markup.PLAYER1.team is 'ENLIGHTENED' then 'ADA Refactor' else 'Jarvis Virus'
                                portal:  lastDestroyEvent.markup.PORTAL1

                lastCaptureEvent = item
                return next()

            if item.markup.TEXT1.plain is ' destroyed an '
                if item.markup.PLAYER1.team is item.markup.PORTAL1.team and not impossibleEvents[item._id]?
                    records.push
                        time:    item.time
                        player:  item.markup.PLAYER1
                        event:   'flip'
                        event2:  if item.markup.PLAYER1.team is 'ENLIGHTENED' then 'Jarvis Virus' else 'ADA Refactor'
                        portal:  item.markup.PORTAL1
                
                if lastDestroyEvent?
                    if lastDestroyEvent.markup.PORTAL1.team isnt item.markup.PORTAL1.team and (lastCaptureEvent is null or lastCaptureEvent.time > lastDestroyEvent.time)
                        if lastDestroyEvent.markup.PLAYER1.team isnt lastDestroyEvent.markup.PORTAL1.team and not impossibleEvents[lastDestroyEvent._id]?
                            records.push
                                time:    lastDestroyEvent.time
                                player:  lastDestroyEvent.markup.PLAYER1
                                event:   'flip'
                                event2:  if lastDestroyEvent.markup.PLAYER1.team is 'ENLIGHTENED' then 'ADA Refactor' else 'Jarvis Virus'
                                portal:  lastDestroyEvent.markup.PORTAL1

                lastDestroyEvent = item
                return next()

            next()

        next()

plugin = 

    name: 'portalhistory'

    init: (callback) ->

        Bot.Server.get '/portalhistory/:guid/:mintimestampms', AccessLevel.LEVEL_TRUSTED, 'Fetch the history of a protal', get_portal_history

        callback()

module.exports = plugin