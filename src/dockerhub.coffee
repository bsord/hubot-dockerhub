# Description
#   Receive DockerHub Web Hook
#
# Devendencies:
#
# Configuration:
#
#   1. DockerHub の Web Hook を設定
#       http://<HUBOT_URL>:<PORT>/hubot/dockerhub/notify
#
# Commands:
#   hubot dockerhub notify <repo> to <room> -- DockerHub の <repo> の Web Hook の通知を <room> に設定
#   hubot dockerhub notify show -- DockerHub の Web Hook の通知先 room を表示
#   hubot dockerhub trigger set <repo> with <token> -- DockerHub の <repo> の build trigger のトークン <token> を設定
#   hubot dockerhub trigger del <repo> -- <repo> の build trigger の設定を削除
#   hubot dockerhub trigger show -- DockerHub の build trigger の設定を表示
#   hubot dockerhub trigger invoke <repo> -- DockerHub の <repo> の build trigger を発火
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
    msg.reply "#{repo} の通知を #{room} に送信します"

  robot.respond /dockerhub\s+notify\s+show\s*$/, (msg) ->
    msg.send "DockerHub の 通知設定一覧"
    repos = (robot.brain.get("dockerhub-notification-repository-to-rooms") || {})
    for repo, rooms of repos
      rooms ||= []
      msg.send "#{repo} -> #{rooms.join(", ")}"

  robot.router.post "/hubot/dockerhub/notify", (req, res) ->
    data = req.body

    ## about JSON payload, see http://docs.docker.com/docker-hub/builds/#webhooks
    robot.logger.info data

    repo = data.repository.repo_name

    rooms = repo2rooms(robot, repo)
    for room in rooms
      robot.messageRoom room, "DockerHub: #{repo} の push に成功しました\n#{data.repository.repo_url}"

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
    robot.logger.debug("hubot-docker build-trigger set")
    repo = res.match[1]
    token = res.match[2]
    robot.logger.debug("repo: #{repo}, token: #{token}")
    trigger_tokens = (robot.brain.get("dockerhub-trigger-tokens") || {})
    trigger_tokens[repo] = token
    robot.brain.set("dockerhub-trigger-tokens", trigger_tokens)
    res.send "#{repo} のトークンを設定しました"

  robot.respond /dockerhub\s+trigger\s+del\s+(\S+)\s*$/, (res) ->
    robot.logger.debug("hubot-docker build-trigger del")
    repo = res.match[1]
    robot.logger.debug("repo: #{repo}")
    trigger_tokens = (robot.brain.get("dockerhub-trigger-tokens") || {})
    if trigger_tokens[repo]
      delete trigger_tokens[repo]
      robot.brain.set("dockerhub-trigger-tokens", trigger_tokens)
      res.send "#{repo} のトークンを削除しました"
    else
      res.send "#{repo} のトークンは設定されていません"

  robot.respond /dockerhub\s+trigger\s+show\s*$/, (res) ->
    robot.logger.debug("hubot-docker build-trigger show")
    trigger_tokens = (robot.brain.get("dockerhub-trigger-tokens") || {})
    num_tokens = Object.keys(trigger_tokens).length
    msg = "#{num_tokens} 件のトークンが設定されています\n"
    for repo, token of trigger_tokens
      msg += "#{repo} : #{token}\n"
    res.send msg

  robot.respond /dockerhub\s+trigger\s+invoke\s+(\S+)\s*$/, (res) ->
    robot.logger.debug("hubot-docker build-trigger invoke")
    repo = res.match[1]
    robot.logger.debug("repo: #{repo}")
    trigger_tokens = (robot.brain.get("dockerhub-trigger-tokens") || {})
    if token = trigger_tokens[repo]
      res.send "#{repo} の build trigger を発火します"
      data = JSON.stringify({"build":true})
      robot.http("https://registry.hub.docker.com/u/#{repo}/trigger/#{token}/")
        .header('Content-Type', 'application/json')
        .post(data) (post_err, post_res, post_body) ->
          robot.logger.debug(post_err)
          robot.logger.debug(post_res)
          robot.logger.debug(post_body)
          if post_err
            res.send "エラーが発生しました: #{post_err}"
          else
            msg = "#{post_res.statusCode}\n"
            for k,v of post_res.headers
              msg += "#{k}: #{v}\n"
            msg += "\n#{post_body}\n"
            res.send msg
    else
      res.send "#{repo} のトークンが設定されていません"

repo2rooms = (robot, repo) ->
  m = (robot.brain.get("dockerhub-notification-repository-to-rooms") || {})
  return (m[repo] || [])
