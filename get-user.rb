require 'Octokit'

# Fetch a user
user = Octokit.user 'githubteacher'
puts user.name
# => "GitHub Sample Teacher"
puts user.fields
puts user.id
puts user.email
# => <Set: {:login, :id, :gravatar_id, :type, :name, :company, :blog, :location, :email, :hireable, :bio, :public_repos, :followers, :following, :created_at, :updated_at, :public_gists}>
puts user[:company]
# => "GitHub, Inc."
user.rels[:gists].href
# => "https://api.github.com/users/githubteacher/gists"
