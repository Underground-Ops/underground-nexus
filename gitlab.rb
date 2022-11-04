external_url 'http://gitlab.underground-ops.me'
#gitlab_rails['initial_root_password'] = File.read('/run/secrets/gitlab_root_password')
nginx['listen_port'] = 80
#nginx['listen_https'] = false
#letsencrypt['enable'] = false
