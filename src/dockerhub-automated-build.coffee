# Description
#   Receive Docker Hub Automated Build Web Hook
#
# Devendencies:
#
# Configuration:
#
#   1. Docker Hub の Web Hook を設定
#       http://<HUBOT_URL>:<PORT>/hubot/dockerhub/automated-build
#
# Commands:
#   hubot dockerhub automated-build <repo> to <room> -- Docker Hub の <repo> の Automated Build の通知を <room> に設定
#   hubot dockerhub automated-build show -- Docker Hub の Automated Build の通知先 room を表示
#
# URLS:
#   POST /hubot/dockerhub/automated-build
#
# Author:
#   YAMADA Tsuyoshi <tyamada@minimum2scp.org>

#url = require('url')
#querystring = require('querystring')

module.exports = (robot) ->
  robot.respond /dockerhub\s+automated-build\s+(\S+)\s+to\s+(\S+)\s*$/, (msg) ->
    unique = (array) ->
      output = {}
      output[array[key]] = array[key] for key in [0...array.length]
      value for key, value of output
    repo = msg.match[1]
    room = msg.match[2]
    m = (robot.brain.get("dockerhub-automated-build-repository-to-rooms") || {})
    r = (m[repo] || [])
    r.push(room)
    m[repo] = unique r
    robot.brain.set("dockerhub-automated-build-repository-to-rooms", m)
    msg.reply "#{repo} の通知を #{room} に送信します"

  robot.respond /dockerhub\s+automated-build\s+show\s*$/, (msg) ->
    msg.send "Docker Hub の Automated Build の通知設定一覧"
    repos = (robot.brain.get("dockerhub-automated-build-repository-to-rooms") || {})
    for repo, rooms of repos
      rooms ||= []
      msg.send "#{repo} -> #{rooms.join(", ")}"

  robot.router.post "/hubot/dockerhub/automated-build", (req, res) ->
    data = req.body

    ## about JSON payload, see http://docs.docker.com/docker-hub/builds/#webhooks
    robot.logger.info data

    repo = data.repository.repo_name

    rooms = repo2rooms(robot, repo)
    for room in rooms
      robot.messageRoom room, "Docker Hub Automated Build: #{repo} の push に成功しました\n#{data.repository.repo_url}"

    ## see https://docs.docker.com/docker-hub/repos/#webhook-chains
    cb_url = data.callback_url
    robot.logger.info cb_url
    robot.http(cb_url)
      .post("{\"state\": \"success\"}") (cb_err, cb_res, cb_body) ->
        robot.logger.debug cb_err
        #robot.logger.debug cb_res
        robot.logger.debug cb_body

    res.end ""

repo2rooms = (robot, repo) ->
  m = (robot.brain.get("dockerhub-automated-build-repository-to-rooms") || {})
  return (m[repo] || [])
