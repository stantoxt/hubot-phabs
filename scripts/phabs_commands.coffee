# Description:
#   enable communication with Phabricator via Conduit api
#
# Dependencies:
#
# Configuration:
#   PHABRICATOR_URL
#   PHABRICATOR_API_KEY
#
# Commands:
#   hubot phab version - give the version of hubot-phabs loaded
#   hubot phab new <project>[:<template>] <name of the task> - creates a new task
#   hubot phab paste <name of the paste> - creates a new paste
#   hubot phab count <project> - counts how many tasks a project has
#   hubot phab bl <id> - blacklists an id from phabs_hear
#   hubot phab unbl <id> - removes an id from blacklist
#   hubot phab Txx - gives information about task Txx
#   hubot phab Txx + <some comment> - add a comment to task Txx
#   hubot phab Txx is <status> - modifies task Txx status
#   hubot phab Txx is <priority> - modifies task Txx priority
#   hubot phab assign Txx to <user> - assigns task Txx to comeone
#   hubot phab Txx next [<key>] - outputs next checkbox found in task Txx
#   hubot phab Txx prev [<key>] - outputs last checked checkbox found in task Txx
#   hubot phab Txx check [<key>] - update task Txx description by checking a box
#   hubot phab Txx uncheck [<key>] - update task Txx description by unchecking a box
#   hubot phab <user> - checks if user is known or not
#   hubot phab me as <email> - makes caller known with <email>
#   hubot phab <user> = <email> - associates user to email
#
# Author:
#   mose

Phabricator = require '../lib/phabricator'
moment = require 'moment'
path = require 'path'

module.exports = (robot) ->
  phab = new Phabricator robot, process.env

  #   hubot phab version - give the version of hubot-phabs loaded
  robot.respond /ph(?:ab)? version *$/, (msg) ->
    pkg = require path.join __dirname, '..', 'package.json'
    msg.send "hubot-phabs module is version #{pkg.version}"
    msg.finish()

  robot.respond /ph phid (.+) *$/, (msg) ->
    phab.getProject(msg.match[1].toLowerCase())
      .then (proj) ->
        msg.send proj.data.phid
      .catch (e) ->
        msg.send e
    msg.finish()

  #   hubot phab new <project>[:<template>] <name of the task>
  robot.respond (
    /ph(?:ab)? new ([-_a-zA-Z0-9]+)(?::([-_a-zA-Z0-9]+))? ([^=]+)(?: = (.*))? *$/
  ), (msg) ->
    phab.withPermission msg, msg.envelope.user, 'phuser', ->
      data = {
        project: msg.match[1].toLowerCase()
        template: msg.match[2]
        title: msg.match[3]
        description: msg.match[4]
        user: msg.envelope.user
      }
      phab.createTask data, (res) ->
        if res.error_info?
          msg.send res.error_info
        else
          phab.recordId res.user, res.id
          msg.send "Task T#{res.id} created = #{res.url}"
    msg.finish()

  #   hubot phab paste <name of the paste> - creates a new paste
  robot.respond /ph(?:ab)? paste (.*)$/, (msg) ->
    phab.withPermission msg, msg.envelope.user, 'phuser', ->
      title = msg.match[1]
      phab.createPaste msg.envelope.user, title, (body) ->
        if body['error_info']?
          msg.send "#{body['error_info']}"
        else
          id = body['result']['object']['id']
          url = process.env.PHABRICATOR_URL + "/paste/edit/#{id}"
          msg.send "Paste P#{id} created = edit on #{url}"
    msg.finish()

  #   hubot phab count <project> - counts how many tasks a project has
  robot.respond (/ph(?:ab)? count ([-_a-zA-Z0-9]+) *$/), (msg) ->
    phab.withProject msg.match[1], (projectData) ->
      if projectData.error_info?
        msg.send projectData.error_info
      else
        phab.listTasks projectData.data.phid, (body) ->
          if Object.keys(body['result']).length is 0
            msg.send "#{projectData.data.name} has no tasks."
          else
            msg.send "#{projectData.data.name} has #{Object.keys(body['result']).length} tasks."
    msg.finish()

  #   hubot bl <id> - blacklists <id> from auto-resopnses
  robot.respond /ph(?:ab)? bl ((?:T|F|P|M|B|Q|L|V)(?:[0-9]+)|(?:r[A-Z]+[a-f0-9]{10,}))/, (msg) ->
    phab.withPermission msg, msg.envelope.user, 'phuser', ->
      phab.blacklist msg.match[1]
      msg.send "Ok. #{msg.match[1]} won't react anymore to auto-detection."
    msg.finish()

  #   hubot bl <id> - blacklists <id> from auto-resopnses
  robot.respond /ph(?:ab)? unbl ((?:T|F|P|M|B|Q|L|V)(?:[0-9]+)|(?:r[A-Z]+[a-f0-9]{10,}))/, (msg) ->
    phab.withPermission msg, msg.envelope.user, 'phuser', ->
      phab.unblacklist msg.match[1]
      msg.send "Ok. #{msg.match[1]} now will react to auto-detection."
    msg.finish()

  #   hubot phab Txx - gives information about task Txxx
  robot.respond /ph(?:ab)?(?: T([0-9]+)| (last))? *$/, (msg) ->
    id = phab.retrieveId(msg.envelope.user, msg.match[1] or msg.match[2])
    unless id?
      msg.send "Sorry, you don't have any task active right now."
      msg.finish()
      return
    phab.taskInfo id, (body) ->
      if body['error_info']?
        msg.send "oops T#{id} #{body['error_info']}"
      else
        phab.withUserByPhid body.result.ownerPHID, (owner) ->
          status = body.result.status
          priority = body.result.priority
          phab.recordId msg.envelope.user, id
          msg.send "T#{id} has status #{status}, " +
                   "priority #{priority}, owner #{owner.name}"
    msg.finish()

  #   hubot phab Txx + <some comment> - add a comment to task Txx
  robot.respond /ph(?:ab)?(?: T([0-9]+)| (last))? \+ (.+) *$/, (msg) ->
    phab.withPermission msg, msg.envelope.user, 'phuser', ->
      id = phab.retrieveId(msg.envelope.user, msg.match[1] or msg.match[2])
      unless id?
        msg.send "Sorry, you don't have any task active right now."
        msg.finish()
        return
      comment = msg.match[3]
      phab.addComment(msg.envelope.user, id, comment)
        .then (body) ->
          msg.send "Ok. Added comment \"#{comment}\" to T#{id}."
        .catch (e) ->
          msg.send "oops T#{id} #{e}"
    msg.finish()

  #   hubot phab Txx in <project-tag> - add a tag to task Txx
  robot.respond /ph(?:ab)?(?: T([0-9]+)| (last))?((?: (?:not in|in) [^ ]+)+) *$/, (msg) ->
    phab.withPermission msg, msg.envelope.user, 'phuser', ->
      id = phab.retrieveId(msg.envelope.user, msg.match[1] or msg.match[2])
      unless id?
        msg.send "Sorry, you don't have any task active right now."
        msg.finish()
        return
      ins = msg.match[3].trim().split('not in ')
      tagin = ins.shift().split('in ').map (e) -> e.trim()
      tagin.shift()
      tagout = [ ]
      for t in ins
        els = t.split('in ')
        tagout.push(els.shift().trim())
        tagin = tagin.concat(els.map (e) -> e.trim())
      phab.changeTags msg.envelope.user, id, tagin, tagout, (body) ->
        if body['error_info']?
          robot.logger.warning body['error_info']
          msg.send body['error_info']
        else
          msg.send body['message']
    msg.finish()

  #   hubot phab Txx is <status> - modifies task Txxx status
  robot.respond new RegExp(
    "ph(?:ab)?(?: T([0-9]+)| (last))? (?:is )?(#{Object.keys(phab.statuses).join('|')})" +
    '(?: (?:=|\\+) (.+))? *$'
  ), (msg) ->
    what = msg.match[1] or msg.match[2]
    status = msg.match[3]
    comment = msg.match[4]
    phab.getPermission(msg.envelope.user, 'phuser')
      .then ->
        phab.getId(msg.envelope.user, what)
      .then (id) ->
        phab.updateStatus(msg.envelope.user, id, status, comment)
      .then (id) ->
        msg.send "Ok, T#{id} now has status #{phab.statuses[status]}."
      .catch (e) ->
        msg.send e
    msg.finish()

  #   hubot phab Txx is <priority> - modifies task Txxx priority
  robot.respond new RegExp(
    "ph(?:ab)?(?: T([0-9]+)| (last))? (?:is )?(#{Object.keys(phab.priorities).join('|')})" +
    '(?: (?:=|\\+) (.+))? *$'
  ), (msg) ->
    what = msg.match[1] or msg.match[2]
    priority = msg.match[3]
    comment = msg.match[4]
    phab.getPermission(msg.envelope.user, 'phuser')
      .then ->
        phab.getId(msg.envelope.user, what)
      .then (id) ->
        phab.updatePriority(msg.envelope.user, id, priority, comment)
      .then (id) ->
        msg.send "Ok, T#{id} now has priority #{priority}."
      .catch (e) ->
        msg.send e
    msg.finish()

  #   hubot phab assign Txx to <user> - assigns task Txxx to comeone
  robot.respond new RegExp(
    'ph(?:ab)?(?: assign)? (?:([^ ]+) (?:to|on) (?:(T)([0-9]+)|(last))|' +
    '(?:T([0-9]+) |(last) )?(?:to|on) ([^ ]+)) *$'
  ), (msg) ->
    if msg.match[2] is 'T'
      who = msg.match[1]
      what = msg.match[3] or msg.match[4]
    else
      who = msg.match[7]
      what = msg.match[5] or msg.match[6]
    assignee = { name: who }
    id = null
    phab.getPermission(msg.envelope.user, 'phuser')
      .then ->
        phab.getId(msg.envelope.user, what)
      .then (id) ->
        phab.getUser(msg.envelope.user, assignee)
      .then (userPhid) ->
        phab.assignTask(id, userPhid)
      .then (id) ->
        msg.send "Ok. T#{id} is now assigned to #{assignee.name}"
      .catch (e) ->
        msg.send e
    msg.finish()

  #   hubot phab Txx next [<key>]- outputs the next checkbox in a given task
  robot.respond /ph(?:ab)?(?: T([0-9]+)| (last))? next(?: (.+))? *$/, (msg) ->
    what = msg.match[1] or msg.match[2]
    key = msg.match[3]
    id = null
    phab.getPermission(msg.envelope.user, 'phuser')
      .bind(id)
      .then ->
        phab.getId(msg.envelope.user, what)
      .then (@id) ->
        phab.nextCheckbox(msg.envelope.user, @id, key)
      .then (line) ->
        msg.send "Next on T#{@id} is: #{line}"
      .catch (e) ->
        msg.send e
    msg.finish()

  #   hubot phab Txx prev [<key>]- outputs the last checked checkbox in a given task
  robot.respond /ph(?:ab)?(?: T([0-9]+)| (last))? prev(?:ious)?(?: (.+))? *$/, (msg) ->
    phab.withPermission msg, msg.envelope.user, 'phuser', ->
      id = phab.retrieveId(msg.envelope.user, msg.match[1] or msg.match[2])
      unless id?
        msg.send "Sorry, you don't have any task active right now."
        msg.finish()
        return
      key = msg.match[3]
      phab.prevCheckbox msg.envelope.user, id, key, (body) ->
        if body.error_info?
          msg.send body.error_info
        else
          msg.send "Previous on T#{id} is: #{body.line}"
    msg.finish()

  #   hubot phab Txx check [<key>] - update task Txx description by checking a box
  robot.respond /ph(?:ab)?(?: T([0-9]+)| (last))? check(!)?(?: ([^\+]+))?(?: \+ (.+))? *$/, (msg) ->
    phab.withPermission msg, msg.envelope.user, 'phuser', ->
      id = phab.retrieveId(msg.envelope.user, msg.match[1] or msg.match[2])
      unless id?
        msg.send "Sorry, you don't have any task active right now."
        msg.finish()
        return
      withNext = msg.match[3]
      key = msg.match[4]
      comment = msg.match[5]
      phab.checkCheckbox msg.envelope.user, id, key, withNext, comment, (body) ->
        if body.error_info?
          msg.send body.error_info
        else
          msg.send "Checked on T#{id}: #{body.line[0]}"
          if body.line[1]?
            msg.send "Next on T#{id}: #{body.line[1]}"
    msg.finish()

  #   hubot phab Txx uncheck [<key>] - update task Txx description by unchecking a box
  robot.respond /ph(?:ab)?(?: T([0-9]+)| (last))? uncheck(!)?(?: ([^\+]+))?(?: \+ (.+))? *$/
  , (msg) ->
    phab.withPermission msg, msg.envelope.user, 'phuser', ->
      id = phab.retrieveId(msg.envelope.user, msg.match[1] or msg.match[2])
      unless id?
        msg.send "Sorry, you don't have any task active right now."
        msg.finish()
        return
      withNext = msg.match[3]
      key = msg.match[4]
      comment = msg.match[5]
      phab.uncheckCheckbox msg.envelope.user, id, key, withNext, comment, (body) ->
        if body.error_info?
          msg.send body.error_info
        else
          msg.send "Unchecked on T#{id}: #{body.line[0]}"
          if body.line[1]?
            msg.send "Previous on T#{id}: #{body.line[1]}"
    msg.finish()

  #   hubot phab user <user> - checks if user is known or not
  robot.respond /ph(?:ab)? (?:user|who) ([^ ]*) *$/, (msg) ->
    assignee = { name: msg.match[1] }
    phab.getPermission(msg.envelope.user, 'phuser')
      .then ->
        phab.getUser(msg.envelope.user, assignee)
      .then (userPhid) ->
        msg.send "Hey I know #{assignee.name}, he's #{userPhid}"
      .catch (e) ->
        msg.send e
    msg.finish()

  #   hubot phab me as <email> - makes caller known with <email>
  robot.respond /ph(?:ab)? me as (.*@.*) *$/, (msg) ->
    email = msg.match[1]
    phab.getPermission(msg.envelope.user, 'phuser')
      .then ->
        msg.envelope.user.email_address = msg.match[1]
        phab.getUser(msg.envelope.user, msg.envelope.user)
      .then (userPhid) ->
        msg.send "Now I know you, you are #{userPhid}"
      .catch (e) ->
        msg.send e
    msg.finish()

  #   hubot phab user <user> = <email> - associates user to email
  robot.respond /ph(?:ab)? user ([^ ]*) *?= *?([^ ]*@.*) *$/, (msg) ->
    assignee = { name: msg.match[1], email_address: msg.match[2] }
    phab.getPermission(msg.envelope.user, 'phuser')
      .then ->
        phab.getUser(msg.envelope.user, assignee)
      .then (userPhid) ->
        msg.send "Now I know #{assignee.name}, he's #{userPhid}"
      .catch (e) ->
        msg.send e
    msg.finish()

  #   hubot phab all <project> search terms - searches for terms in project
  robot.respond /ph(?:ab)? all ([^ ]+) (.+)$/, (msg) ->
    project = msg.match[1].toLowerCase()
    terms = msg.match[2]
    phab.getProject(project)
      .then (proj) ->
        phab.searchAllTask proj.data.phid, terms, (payload) ->
          if payload.result.data.length is 0
            msg.send "There is no task matching '#{terms}' in project '#{proj.data.name}'."
          else
            for task in payload.result.data
              msg.send "#{process.env.PHABRICATOR_URL}/T#{task.id} - #{task.fields['name']}"
            if payload.result.cursor.after?
              msg.send '... and there is more.'
      .catch (e) ->
        msg.send e
    msg.finish()

  #   hubot phab <project> search terms - searches for terms in project
  robot.respond /ph(?:ab)? ([^ ]+) (.+)$/, (msg) ->
    project = msg.match[1].toLowerCase()
    terms = msg.match[2]
    phab.getProject(project)
      .then (proj) ->
        phab.searchTask proj.data.phid, terms, (payload) ->
          if payload.result.data.length is 0
            msg.send "There is no task matching '#{terms}' in project '#{proj.data.name}'."
          else
            for task in payload.result.data
              msg.send "#{process.env.PHABRICATOR_URL}/T#{task.id} - #{task.fields['name']}"
            if payload.result.cursor.after?
              msg.send '... and there is more.'
      .catch (e) ->
        msg.send e
    msg.finish()
