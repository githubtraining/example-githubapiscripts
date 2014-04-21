#!/usr/bin/env ruby

require 'octokit'

pass_re = /^password: "(.*)"$/
token = '***** GET A TOKEN *****'

c = Octokit::Client.new(:access_token => token)
user_login = c.user.login

puts "Finding your mentions...\n"
notifications = 50.times.map {|x| c.notifications(:page => x+1)}.take_while {|x| x.count > 1}.inject([]) {|acc,x| acc.concat(x); acc}
repos = notifications.map {|x| x.repository.full_name}.sort.uniq

puts "Fetching contributors from #{repos.count} repos...\n"
contrib = repos.map do |x| 
  begin
    contrib = c.contributors(x)
    raise "wtf" unless contrib.is_a?(Array)
    ret = [x, contrib]
  rescue
    ## NB: When you fetch from a repo that has never been contributed to 
    ## by anyone, the API throws a 404
    ret = [x, []]
  end
end

to_unsub = contrib.select {|x| ! x[1].any? {|y| y[:login] == user_login } }.map {|x| x[0]}

if (ARGV[0] == "-f")
  puts "Unsubscribing from #{to_unsub.count} repos..."
  to_unsub.each {|x| puts x; c.delete_subscription(x) }
else
  puts "\nYou should unsubscribe from:"
  to_unsub.each {|x| puts "#{x} - https://github.com/#{x}" }

  puts "\nRerun with -f to unsubscribe"
end
