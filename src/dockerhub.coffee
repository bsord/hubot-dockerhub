# Description
#   Receive DockerHub Web Hook
#
# Devendencies:
#
# Configuration:
#
#   1. Set dockerhub webhook
#       http://<HUBOT_URL>:<PORT>/hubot/dockerhub/notify
#
# Commands:
#   hubot dockerhub notify <repo> to <room> -- Set webhook notification for DockerHub <repo> to <room>
#   hubot dockerhub notify show -- Show webhook notification
#   hubot dockerhub trigger set <repo> with <token> -- Set dockerhub build trigger token <token> for <repo>
#   hubot dockerhub trigger del <repo> -- Remove dockerhub build trigger token for <repo>
#   hubot dockerhub trigger show -- Show dockerhub build triggers
#   hubot dockerhub trigger invoke <repo> -- Trigger dockerhub build for <repo>
#
# URLS:
#   POST /hubot/dockerhub/notify
#
# Author:
#   YAMADA Tsuyoshi <tyamada@minimum2scp.org>

#url = require('url')
#querystring = require('querystring')

module.exports = (robot) ->
  robot.respond /dockerhub\s+notify\s+(\S+)\s+to\s+(\S+)\s*$/, (msg) ->
    unique = (array) ->
      output = {}
      output[array[key]] = array[key] for key in [0...array.length]
      value for key, value of output
    repo = msg.match[1]
    room = msg.match[2]
    m = (robot.brain.get("dockerhub-notification-repository-to-rooms") || {})
    r = (m[repo] || [])
    r.push(room)
    m[repo] = unique r
    robot.brain.set("dockerhub-notification-repository-to-rooms", m)
    msg.send "Send notification for #{repo} to room #{room}"

  robot.respond /dockerhub\s+notify\s+show\s*$/, (msg) ->
    repos = (robot.brain.get("dockerhub-notification-repository-to-rooms") || {})
    msg.send "DockerHub notification list\n" + (repo + "-> " + (rooms||[]).join(", ") for repo, rooms of repos).join("\n")

  robot.router.post "/hubot/dockerhub/notify", (req, res) ->
    data = req.body

    ## about JSON payload, see http://docs.docker.com/docker-hub/builds/#webhooks
    robot.logger.info data

    repo = data.repository.repo_name
    tag = data.push_data.tag

    rooms = repo2rooms(robot, repo)
    for room in rooms
      robot.messageRoom room, attachments:[
        color:       "good",
        title:       "DockerHub",
        title_link:  "https://hub.docker.com/",
        text:        "<#{data.repository.repo_url}|#{repo}:#{tag}> was pushed",
        fallback:    "DockerHub: #{repo}:#{tag} was pushed\n#{data.repository.repo_url}"
      ]

    ## see https://docs.docker.com/docker-hub/repos/#webhook-chains
    cb_url = data.callback_url
    robot.logger.info cb_url
    robot.http(cb_url)
      .post("{\"state\": \"success\"}") (cb_err, cb_res, cb_body) ->
        robot.logger.debug cb_err
        #robot.logger.debug cb_res
        robot.logger.debug cb_body

    res.end ""

  robot.respond /dockerhub\s+trigger\s+set\s+(\S+)\s+with\s+(\S+)\s*$/, (res) ->
    repo = res.match[1]
    token = res.match[2]
    trigger_tokens = (robot.brain.get("dockerhub-trigger-tokens") || {})
    trigger_tokens[repo] = token
    robot.brain.set("dockerhub-trigger-tokens", trigger_tokens)
    res.send "Set token for #{repo}"

  robot.respond /dockerhub\s+trigger\s+del\s+(\S+)\s*$/, (res) ->
    repo = res.match[1]
    trigger_tokens = (robot.brain.get("dockerhub-trigger-tokens") || {})
    if trigger_tokens[repo]
      delete trigger_tokens[repo]
      robot.brain.set("dockerhub-trigger-tokens", trigger_tokens)
      res.send "Removed token for #{repo}"
    else
      res.send "No token for #{repo}"

  robot.respond /dockerhub\s+trigger\s+show\s*$/, (res) ->
    trigger_tokens = (robot.brain.get("dockerhub-trigger-tokens") || {})
    num_tokens = Object.keys(trigger_tokens).length
    messages = []
    res.send "#{num_tokens} tokens exist.\n" + ("#{repo} : #{token}" for repo, token of trigger_tokens).join("\n")

  robot.respond /dockerhub\s+trigger\s+invoke\s+(\S+)\s*$/, (res) ->
    repo = res.match[1]
    trigger_tokens = (robot.brain.get("dockerhub-trigger-tokens") || {})
    if token = trigger_tokens[repo]
      res.send "Triggered #{repo}"
      data = JSON.stringify({"build":true})
      robot.http("https://registry.hub.docker.com/u/#{repo}/trigger/#{token}/")
        .header('Content-Type', 'application/json')
        .post(data) (post_err, post_res, post_body) ->
          robot.logger.debug(post_err)
          robot.logger.debug(post_res)
          robot.logger.debug(post_body)
          if post_err
            res.send "Error: #{post_err}"
          else
            msg = "#{post_res.statusCode}\n"
            for k,v of post_res.headers
              msg += "#{k}: #{v}\n"
            msg += "\n#{post_body}\n"
            res.send msg
    else
      res.send "No token for #{repo}"

repo2rooms = (robot, repo) ->
  m = (robot.brain.get("dockerhub-notification-repository-to-rooms") || {})
  return (m[repo] || [])
