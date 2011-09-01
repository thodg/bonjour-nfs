#!/usr/bin/env ruby
#
#  Bonjour NFS mount daemon
#  Copyright 2007 Sander Van Woensel
#  Copyright 2011 Thomas de Grivel <billitch@gmail.com>
#  Please read LICENSE.txt
#
#  Version::   0.9

require 'rubygems'
require 'dnssd'
require 'pathname'
require 'fileutils'
require 'daemons'
require 'logger'
require 'getoptlong'

class BonjourNFSMounter
  MAIN_LOOP_DELAY = 15
  NFS_SERVICE = '_nfs._tcp'

  def initialize
  end

  def main(log_target)
    $log = Logger.new(log_target, 1, 512000) # Logfile can be at most 500kB.
    $log.level = Logger::INFO # Log information and higher classes.
    $log.info("Started")
    begin
      main_loop
    rescue StandardError => e
      $log.error(e.to_s)
    ensure
      $log.info("Stopped")
    end
  end

  def main_loop
    i = 0
    # NOTE: Discovery of new mounts will be detected SKIP_MOUNT_RETRIEVAL_COUNT
    # times more faster.
    loop do
      @active_mounts = get_active_mounts
      discover_nfs
      sleep(MAIN_LOOP_DELAY)
    end
  end

  def get_active_mounts
    mounts = Array.new
    nfs_mounts = `mount -t nfs 2>&1 || echo bonjour-nfs error`.split("\n")
    for nfs_mount in nfs_mounts do
      if nfs_mount == 'bonjour-nfs error'
        raise 'in get_active_mounts: '+nfs_mounts[0].chomp()
      end
      server_path = nfs_mount.split()[0]
      unless server_path.nil?
        (server, path) = server_path.split(':')
        m = Mount.new(server, Mount::UNKNOWN_PORT, path)
        p m
        mounts.push(m)
      end
    end

    mounts
  end
  private :get_active_mounts

  def discover_nfs
    @service = DNSSD.browse(NFS_SERVICE) do |browse_reply|
      # Found a NFS service, resolve it.
      DNSSD.resolve(browse_reply.name,
                    browse_reply.type,
                    browse_reply.domain,
                    0,
                    browse_reply.interface) do |resolve_reply|

        mount = Mount.new(resolve_reply.name, resolve_reply.port, resolve_reply.text_record['path'])
        if !@active_mounts.include?(mount)
          # TODO: probe if directory could be created!!.

          if FileUtils.mkdir(mount.mount_point)
            if system("mount -t nfs -o resvport,udp,rwsize=16384,locallock,port=#{mount.port} '#{mount.server}:#{mount.path}' '#{mount.mount_point}'")
              @active_mounts.push(mount)
              $log.info("Succesfully mounted dicovered NFS service "+mount.to_s)
            else
              $log.error("Failed to mount discovered NFS service: #{mount.to_s}. Error code #{$?}.")
              FileUtils.rmdir(mount.mount_point)
            end
          end
        end
      end

    end

  end
  private :discover_nfs

end

class Mount

  MOUNT_POINT_ROOT = File::SEPARATOR+'Volumes'
  UNKNOWN_PORT = -1

  attr_reader :server
  attr_reader :port
  attr_reader :path

  def initialize(server, port, path)
    @server = server.chomp('.').chomp('.local')
    @port = port
    @path = path
    @mount_point = nil
  end

  def ==(other_mount)
    # NOTE: Port not checked for equality.
    @server.downcase == other_mount.server.downcase and
      @path.downcase == other_mount.path.downcase
  end

  def mount_point
    if @mount_point.nil?
      i=1

      mount_point = Pathname.new(MOUNT_POINT_ROOT)
      mount_point += @path.split(File::SEPARATOR).last
      new_mount_point = mount_point

      # Add an ever increasing number to the mount_point when the path already exists.
      while File.exists?(new_mount_point)
        new_mount_point = Pathname.new(mount_point.to_s+' ('+i.to_s+')')
        i+=1

        # When we had to count up to 10 and still did not find a valid path, something is really wrong.
        if i>10
          $log.error("Could not find a not existing mount point.")
          return
        end
      end

      @mount_point = new_mount_point
    end

    @mount_point
  end

  def to_s
    "nfs://#{server}:#{@port}#{@path} at #{@mount_point}"
  end
end

#------------------------------------------------------------------------------#
#                                    Main                                      #
#------------------------------------------------------------------------------#


if __FILE__ == $0
  if Process.euid != 0
    STDERR << "bonjour-nfs needs root privileges\n"
    Process.exit
  end

  debug = false
  foreground = false
  opts = GetoptLong.new(['--debug', '-d', GetoptLong::NO_ARGUMENT],
                        ['--foreground', '-f', GetoptLong::NO_ARGUMENT])
  opts.each do |opt, arg|
    case opt
    when '--debug'
      debug = true
    when '--foreground'
      foreground = true
    end
  end
  foreground = true if debug

  Process.setpriority(Process::PRIO_PROCESS, 0, 19)
  Daemonize.daemonize unless foreground

  log_target = if debug then STDOUT else '/Library/Logs/bonjour-nfs.log' end

  bonjournfsm = BonjourNFSMounter.new
  bonjournfsm.main(log_target)
end
