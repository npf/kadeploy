# To be used as you're using Open3.popen3 in ruby 1.9.2
class Execute
  attr_reader :command, :exec_pid, :stdout, :stderr, :status

  def initialize(*cmd)
    @command = *cmd

    @exec_pid = nil

    @stdout = nil
    @stderr = nil
    @status = nil

    @child_io, @parent_io = Execute.init_ios()
  end

  def self.[](*cmd)
    self.new(*cmd)
  end

  def self.init_ios(opts={})
    in_r, in_w = IO::pipe
    in_w.sync = true

    out_r, out_w = IO::pipe
    err_r, err_w = IO::pipe

    [ [in_r,out_w,err_w], [in_w,out_r,err_r] ]
  end

  def run(opts={})
    @child_io, @parent_io = Execute.init_ios(opts) unless @child_io and @parent_io
    @exec_pid = fork {
      @parent_io.each { |io| io.close unless io.closed? }
      std = [STDIN, STDOUT, STDERR]
      std.each_index do |i|
        std[i].reopen(@child_io[i])
        @child_io[i].close
      end
      exec(*@command)
    }

    @child_io.each { |io| io.close unless io.closed? }
    result = [@exec_pid, *@parent_io]
    if block_given?
      begin
        return yield(*result)
      ensure
        wait(opts)
      end
    end
    result
  end

  def run!(opts={})
    if block_given?
      run(opts,Proc.new)
    else
      run(opts)
    end
    self
  end

  def wait(opts={})
    unless @exec_pid.nil?
      begin
        if opts[:stdout_size]
          @stdout = @parent_io[1].read(opts[:stdout_size]) unless @parent_io[1].closed?
          @parent_io[1].read unless @parent_io[1].closed?
        else
          @stdout = @parent_io[1].read unless @parent_io[1].closed?
        end
        if opts[:stderr_size]
          @stderr = @parent_io[2].read(opts[:stderr_size]) unless @parent_io[2].closed?
          @parent_io[2].read unless @parent_io[2].closed?
        else
          @stderr = @parent_io[2].read unless @parent_io[2].closed?
        end

        _, @status = Process.wait2(@exec_pid)
      rescue Errno::ECHILD
        @status = nil
      ensure
        @parent_io.each { |io| io.close unless io.closed? }
        @child_io = nil
        @parent_io = nil
        @exec_pid = nil
      end
      [ @status, @stdout, @stderr ]
    end
  end

  def self.kill_recursive(pid)
    begin
      # SIGSTOPs the process to avoid it creating new childs
      Process.kill('STOP',pid)
      # Gather the list of childs before killing the parent in order to
      # be able to kill childs that will be re-attached to init
      childs = `ps --ppid #{pid} -o pid=`.split("\n").collect!{|p| p.strip.to_i}
      # Directly kill the process not to generate <defunct> childs
      Process.kill('KILL',pid)
      childs.each do |cpid|
        kill_recursive(cpid)
      end
    rescue Errno::ESRCH
    end
  end

  def kill()
    @parent_io.each { |io| io.close unless io.closed? } if @parent_io
    @child_io.each { |io| io.close unless io.closed? } if @child_io
    unless @exec_pid.nil?
      begin
        Execute.kill_recursive(@exec_pid)
        Process.wait(@exec_pid)
      rescue Errno::ESRCH
      end
      @exec_pid = nil
    end
  end

  def self.do(*cmd,&block)
    child_io, parent_io = init_ios()

    pid = fork {
      parent_io.each { |io| io.close }
      std = [STDIN, STDOUT, STDERR]
      std.each_index do |i|
        std[i].reopen(child_io[i])
        child_io[i].close
      end
      exec(*cmd)
    }

    child_io.each { |io| io.close }
    result = [pid, *parent_io]
    if block_given?
      begin
        return yield(*result)
      ensure
        parent_io.each { |io| io.close unless io.closed? }
        begin
          Process.wait(pid)
        rescue Errno::ECHILD
        end
      end
    end
    result
  end
end
