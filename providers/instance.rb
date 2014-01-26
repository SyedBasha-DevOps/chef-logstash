#
# Cookbook Name:: logstash
# Provider:: instance
# Author:: John E. Vincent
# License:: Apache 2.0
#
# Copyright 2014, John E. Vincent

require 'chef/mixin/shell_out'
require 'chef/mixin/language'
include Chef::Mixin::ShellOut

def load_current_resource
  @base_directory = new_resource.base_directory
  @install_type = new_resource.install_type
  @version = new_resource.version || node['logstash']['default_version']
  @checksum = new_resource.checksum || node['logstash']['default_checksum']
  @source_url = new_resource.source_url || "https://download.elasticsearch.org/logstash/logstash/logstash-#{@version}-flatjar.jar"
  @repo = new_resource.repo
  @sha = new_resource.sha
  @java_home = new_resource.java_home
  @ls_user = new_resource.user
  @ls_group = new_resource.group
  @ls_useropts = new_resource.user_opts
  @do_symlink = new_resource.auto_symlink
  @instance_dir = "#{@base_directory}/#{new_resource.name}"
  @updated = false
end

action :create do

  ur = user @ls_user do
    home @ls_useropts[:homedir]
    system true
    action :create
    manage_home true
    uid @ls_useropts[:uid]
  end
  set_updated(ur.updated_by_last_action?)

  gr = group @ls_group do
    members @ls_user
    append true
    system true
  end
  set_updated(gr.updated_by_last_action?)

  bdr = directory @base_directory do
    action :create
    mode '0755'
    owner @ls_user
    group @ls_group
  end
  set_updated(bdr.updated_by_last_action?)

  idr = directory @instance_dir do
    action :create
    mode '0755'
    owner @ls_user
    group @ls_group
  end
  set_updated(idr.updated_by_last_action?)

  %w{bin etc lib log tmp etc/conf.d etc/patterns}.each do |ldir|
    r = directory "#{@instance_dir}/ldir" do
      action :create
      mode '0755'
      owner @ls_user
      group @ls_group
    end
    set_updated(r.updated_by_last_action?)
  end

  if @install_type == "jar"
    rfr = remote_file "#{@instance_dir}/lib/logstash-#{@version}.jar" do
      owner 'root'
      group 'root'
      mode '0755'
      source @source_url
      checksum @checksum
    end
    set_updated(rfr.updated_by_last_action?)

    lr = link "#{@instance_dir}/lib/logstash.jar" do
      to "#{@instance_dir}/lib/logstash-#{@version}.jar"
      not_if { @do_symlink }
    end
    set_updated(lr.updated_by_last_action?)
  elsif @install_type == "source"
    sd = directory "#{@instance_dir}/source" do
      action :create
      owner @ls_user
      group @ls_group
      mode '0755'
    end
    set_updated(sd.updated_by_last_action?)

    gr = git "#{@instance_dir}/source" do
      repository @repo
      reference @sha
      action :sync
      user @ls_user
      group @ls_group
    end
    set_updated(gr.updated_by_last_action?)

    source_version = @sha || "v#{@version}"
    er = execute "build-logstash" do
      cwd "#{@instance_dir}/source"
      environment(:JAVA_HOME => @java_home)
      user @ls_user # Changed from root cause building as root...WHA?
      command "make clean && make VERSION=#{source_version} jar"
      action :run
      creates "#{@instance_dir}/source/build/logstash-#{source_version}--monolithic.jar"
      not_if "test -f #{@instance_dir}/source/build/logstash-#{source_version}--monolithic.jar"
    end
    set_updated(er.updated_by_last_action?)
    lr = link "#{@instance_dir}/lib/logstash.jar" do
      to "#{@instance_dir}/source/build/logstash-#{source_version}--monolithic.jar"
    end
    set_updated(lr.updated_by_last_action?)
  else
    Chef::Application.fatal!("Unknown install type: #{@install_type}")
  end
end

private
def set_updated(u)
  @updated = u unless @updated == true
end
