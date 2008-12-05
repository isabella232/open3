#
# = open3.rb: Popen, but with stderr, too
#
# Author:: Yukihiro Matsumoto
# Documentation:: Konrad Meyer
#
# Open3 gives you access to stdin, stdout, and stderr when running other
# programs.
#

#
# Open3 grants you access to stdin, stdout, stderr and a thread to wait the
# child process when running another program.
#
# - Open3.popen3 : pipes for stdin, stdout, stderr
# - Open3.popen2 : pipes for stdin, stdout
# - Open3.popen2e : pipes for stdin, merged stdout and stderr
# - Open3.poutput3 : give a string for stdin.  get strings for stdout, stderr
# - Open3.poutput2 : give a string for stdin.  get a string for stdout
# - Open3.poutput2e : give a string for stdin.  get a string for merged stdout and stderr
# - Open3.pipeline_rw : pipes for first stdin and last stdout of a pipeline
# - Open3.pipeline_r : pipe for last stdout of a pipeline
# - Open3.pipeline_w : pipe for first stdin of a pipeline
# - Open3.pipeline_start : a pipeline
# - Open3.pipeline : run a pipline and wait
#

module Open3

  # Open stdin, stdout, and stderr streams and start external executable.
  # In addition, a thread for waiting the started process is noticed.
  # The thread has a pid method and thread variable :pid which is the pid of
  # the started process.
  #
  # Block form:
  #
  #   Open3.popen3(cmd... [, opts]) {|stdin, stdout, stderr, wait_thr|
  #     pid = wait_thr.pid # pid of the started process.
  #     ...
  #     exit_status = wait_thr.value # Process::Status object returned.
  #   }
  #
  # Non-block form:
  #   
  #   stdin, stdout, stderr, wait_thr = Open3.popen3(cmd... [, opts])
  #   pid = wait_thr[:pid]  # pid of the started process.
  #   ...
  #   stdin.close  # stdin, stdout and stderr should be closed explicitly in this form.
  #   stdout.close
  #   stderr.close
  #   exit_status = wait_thr.value  # Process::Status object returned.
  #
  # The parameters +cmd...+ is passed to Kernel#spawn.
  # So a commandline string and list of argument strings can be accepted as follows.
  #
  #   Open3.popen3("echo a") {|i, o, e, t| ... }
  #   Open3.popen3("echo", "a") {|i, o, e, t| ... }
  #   Open3.popen3(["echo", "argv0"], "a") {|i, o, e, t| ... }
  #
  # If the last parameter, opts, is a Hash, it is recognized as an option for Kernel#spawn.
  #
  #   Open3.popen3("pwd", :chdir=>"/") {|i,o,e,t|
  #     p o.read.chomp #=> "/"
  #   }
  #
  # wait_thr.value waits the termination of the process.
  # The block form also waits the process when it returns.
  #
  # Closing stdin, stdout and stderr does not wait the process.
  #
  def popen3(*cmd, &block)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[:in] = in_r
    in_w.sync = true

    out_r, out_w = IO.pipe
    opts[:out] = out_w

    err_r, err_w = IO.pipe
    opts[:err] = err_w

    popen_run(cmd, opts, [in_r, out_w, err_w], [in_w, out_r, err_r], &block)
  end
  module_function :popen3

  # Open3.popen2 is similer to Open3.popen3 except it doesn't make a pipe for
  # the standard error stream.
  #
  # Block form:
  #
  #   Open3.popen2(cmd... [, opts]) {|stdin, stdout, wait_thr|
  #     pid = wait_thr.pid # pid of the started process.
  #     ...
  #     exit_status = wait_thr.value # Process::Status object returned.
  #   }
  #
  # Non-block form:
  #   
  #   stdin, stdout, wait_thr = Open3.popen2(cmd... [, opts])
  #   ...
  #   stdin.close  # stdin and stdout should be closed explicitly in this form.
  #   stdout.close
  #
  # Example:
  #
  #   Open3.popen2("wc -c") {|i,o,t|
  #     i.print "answer to life the universe and everything"
  #     i.close
  #     p o.gets #=> "42\n"
  #   }
  #
  #   Open3.popen2("bc -q") {|i,o,t| 
  #     i.puts "obase=13"
  #     i.puts "6 * 9"
  #     p o.gets #=> "42\n"
  #   }
  #
  #   Open3.popen2("dc") {|i,o,t|
  #     i.print "42P"                                       
  #     i.close
  #     p o.read #=> "*"
  #   }
  #
  def popen2(*cmd, &block)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[:in] = in_r
    in_w.sync = true

    out_r, out_w = IO.pipe
    opts[:out] = out_w

    popen_run(cmd, opts, [in_r, out_w], [in_w, out_r], &block)
  end
  module_function :popen2

  # Open3.popen2e is similer to Open3.popen3 except it merges
  # the standard output stream and the standard error stream.
  #
  # Block form:
  #
  #   Open3.popen2e(cmd... [, opts]) {|stdin, stdout_and_stderr, wait_thr|
  #     pid = wait_thr.pid # pid of the started process.
  #     ...
  #     exit_status = wait_thr.value # Process::Status object returned.
  #   }
  #
  # Non-block form:
  #   
  #   stdin, stdout_and_stderr, wait_thr = Open3.popen2e(cmd... [, opts])
  #   ...
  #   stdin.close  # stdin and stdout_and_stderr should be closed explicitly in this form.
  #   stdout_and_stderr.close
  #
  def popen2e(*cmd, &block)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[:in] = in_r
    in_w.sync = true

    out_r, out_w = IO.pipe
    opts[[:out, :err]] = out_w

    popen_run(cmd, opts, [in_r, out_w], [in_w, out_r], &block)
  end
  module_function :popen2e

  def popen_run(cmd, opts, child_io, parent_io) # :nodoc:
    pid = spawn(*cmd, opts)
    wait_thr = Process.detach(pid)
    child_io.each {|io| io.close }
    result = [*parent_io, wait_thr]
    if defined? yield
      begin
	return yield(*result)
      ensure
	parent_io.each{|io| io.close unless io.closed?}
        wait_thr.join
      end
    end
    result
  end
  module_function :popen_run
  class << self
    private :popen_run
  end

  # Open3.poutput3 captures the standard output and the standard error of a command.
  #
  #   stdout_str, stderr_str, status = Open3.poutput3(cmd... [, opts])
  #
  # The arguments cmd and opts are passed to Open3.popen3 except opts[:stdin_data].
  #
  # If opts[:stdin_data] is specified, it is sent to the command's standard input.
  #
  # Example:
  #
  #   # dot is a command of graphviz.
  #   graph = <<'End'
  #     digraph g {
  #       a -> b
  #     }
  #   End
  #   layouted_graph, dot_log = Open3.poutput3("dot -v", :stdin_data=>graph)
  #
  #   o, e, s = Open3.poutput3("echo a; sort >&2", :stdin_data=>"foo\nbar\nbaz\n")
  #   p o #=> "a\n"
  #   p e #=> "bar\nbaz\nfoo\n"
  #   p s #=> #<Process::Status: pid 32682 exit 0>
  #
  def poutput3(*cmd, &block)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    stdin_data = opts.delete(:stdin_data) || ''

    popen3(*cmd, opts) {|i, o, e, t|
      out_reader = Thread.new { o.read }
      err_reader = Thread.new { e.read }
      i.write stdin_data
      i.close
      [out_reader.value, err_reader.value, t.value]
    }
  end
  module_function :poutput3

  # Open3.poutput2 captures the standard output of a command.
  #
  #   stdout_str, status = Open3.poutput2(cmd... [, opts])
  #
  # The arguments cmd and opts are passed to Open3.popen2 except opts[:stdin_data].
  #
  # If opts[:stdin_data] is specified, it is sent to the command's standard input.
  #
  #   # factor is a command for integer factorization
  #   o, s = Open3.poutput2("factor", :stdin_data=>"42")    
  #   p o #=> "42: 2 3 7\n"
  #
  def poutput2(*cmd, &block)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    stdin_data = opts.delete(:stdin_data) || ''

    popen2(*cmd, opts) {|i, o, t|
      out_reader = Thread.new { o.read }
      i.write stdin_data
      i.close
      [out_reader.value, t.value]
    }
  end
  module_function :poutput2

  # Open3.poutput2e captures the standard output and the standard error of a command.
  #
  #   stdout_and_stderr_str, status = Open3.poutput2e(cmd... [, opts])
  #
  # The arguments cmd and opts are passed to Open3.popen2e except opts[:stdin_data].
  #
  # If opts[:stdin_data] is specified, it is sent to the command's standard input.
  #
  def poutput2e(*cmd, &block)
    if Hash === cmd.last
      opts = cmd.pop.dup
    else
      opts = {}
    end

    stdin_data = opts.delete(:stdin_data) || ''

    popen2e(*cmd, opts) {|i, oe, t|
      outerr_reader = Thread.new { oe.read }
      i.write stdin_data
      i.close
      [outerr_reader.value, t.value]
    }
  end
  module_function :poutput2e

  # Open3.pipeline_rw starts list of commands as a pipeline with pipes
  # which connects stdin of the first command and stdout of the last command.
  #
  #   Open3.pipeline_rw(cmd1, cmd2, ... [, opts]) {|first_stdin, last_stdout, wait_threads|
  #     ...
  #   }
  #
  #   first_stdin, last_stdout, wait_threads = Open3.pipeline_rw(cmd1, cmd2, ... [, opts])
  #   ...
  #   first_stdin.close
  #   last_stdout.close
  #
  # Each cmd is a string or an array.
  # If it is an array, the elements are passed to Kernel#spawn.
  #
  # The option to pass Kernel#spawn is constructed by merging
  # +opts+, the last hash element of the array and
  # specification for the pipe between each commands.
  #
  # Example:
  #
  #   Open3.pipeline_rw("tr -dc A-Za-z", "wc -c") {|i,o,ts|
  #     i.puts "All persons more than a mile high to leave the court."
  #     i.close
  #     p o.gets #=> "42\n"
  #   }
  #
  #   Open3.pipeline_rw("sort", "cat -n") {|stdin, stdout, wait_thrs|
  #     stdin.puts "foo"
  #     stdin.puts "bar"
  #     stdin.puts "baz"
  #     stdin.close     # send EOF to sort.
  #     p stdout.read   #=> "     1\tbar\n     2\tbaz\n     3\tfoo\n"
  #   }
  def pipeline_rw(*cmds, &block)
    if Hash === cmds.last
      opts = cmds.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[:in] = in_r
    in_w.sync = true

    out_r, out_w = IO.pipe
    opts[:out] = out_w

    pipeline_run(cmds, opts, [in_r, out_w], [in_w, out_r], &block)
  end
  module_function :pipeline_rw

  # Open3.pipeline_r starts list of commands as a pipeline with a pipe
  # which connects stdout of the last command.
  #
  #   Open3.pipeline_r(cmd1, cmd2, ... [, opts]) {|last_stdout, wait_threads|
  #     ...
  #   }
  #
  #   last_stdout, wait_threads = Open3.pipeline_r(cmd1, cmd2, ... [, opts])
  #   ...
  #   last_stdout.close
  #
  # Example:
  #
  #   fname = "/usr/share/man/man1/ls.1.gz"
  #   Open3.pipeline_r(["zcat", fname], "nroff -man", "colcrt") {|r, ts|
  #     IO.copy_stream(r, STDOUT)
  #   }
  #
  #   Open3.pipeline_r("zcat /var/log/apache2/access.log.*.gz",
  #                    [{"LANG"=>"C"}, "grep", "GET /favicon.ico"],
  #                    "logresolve") {|r, ts|
  #     r.each_line {|line|
  #       ...
  #     }
  #   }
  #
  #   Open3.pipeline_r("yes", "head -10") {|r, ts|
  #     p r.read      #=> "y\ny\ny\ny\ny\ny\ny\ny\ny\ny\n"
  #     p ts[0].value #=> #<Process::Status: pid 24910 SIGPIPE (signal 13)>
  #     p ts[1].value #=> #<Process::Status: pid 24913 exit 0>
  #   }
  #
  def pipeline_r(*cmds, &block)
    if Hash === cmds.last
      opts = cmds.pop.dup
    else
      opts = {}
    end

    out_r, out_w = IO.pipe
    opts[:out] = out_w

    pipeline_run(cmds, opts, [out_w], [out_r], &block)
  end
  module_function :pipeline_r

  # Open3.pipeline_w starts list of commands as a pipeline with a pipe
  # which connects stdin of the first command.
  #
  #   Open3.pipeline_w(cmd1, cmd2, ... [, opts]) {|first_stdin, wait_threads|
  #     ...
  #   }
  #
  #   first_stdin, wait_threads = Open3.pipeline_w(cmd1, cmd2, ... [, opts])
  #   ...
  #   first_stdin.close
  #
  # Example:
  #
  #   Open3.pipeline_w("bzip2 -c", :out=>"/tmp/hello.bz2") {|w, ts|
  #     w.puts "hello" 
  #   }
  #
  def pipeline_w(*cmds, &block)
    if Hash === cmds.last
      opts = cmds.pop.dup
    else
      opts = {}
    end

    in_r, in_w = IO.pipe
    opts[:in] = in_r
    in_w.sync = true

    pipeline_run(cmds, opts, [in_r], [in_w], &block)
  end
  module_function :pipeline_w

  # Open3.pipeline_start starts list of commands as a pipeline.
  # No pipe made for stdin of the first command and
  # stdout of the last command.
  #
  #   Open3.pipeline_start(cmd1, cmd2, ... [, opts]) {|wait_threads|
  #     ...
  #   }
  #
  #   wait_threads = Open3.pipeline_start(cmd1, cmd2, ... [, opts])
  #   ...
  #
  def pipeline_start(*cmds, &block)
    if Hash === cmds.last
      opts = cmds.pop.dup
    else
      opts = {}
    end

    pipeline_run(cmds, opts, [], [], &block)
  end
  module_function :pipeline_start

  # Open3.pipeline starts list of commands as a pipeline.
  # It waits the finish of the commands.
  # No pipe made for stdin of the first command and
  # stdout of the last command.
  #
  #   status_list = Open3.pipeline(cmd1, cmd2, ... [, opts])
  #
  # Example:
  #
  #   fname = "/usr/share/man/man1/ruby.1.gz"
  #   p Open3.pipeline(["zcat", fname], "nroff -man", "less")   
  #   #=> [#<Process::Status: pid 11817 exit 0>,
  #   #    #<Process::Status: pid 11820 exit 0>,
  #   #    #<Process::Status: pid 11828 exit 0>]
  #
  #   # count lines
  #   Open3.pipeline("sort", "uniq -c", :in=>"names.txt", :out=>"count")
  #
  def pipeline(*cmds)
    if Hash === cmds.last
      opts = cmds.pop.dup
    else
      opts = {}
    end

    pipeline_run(cmds, opts, [], []) {|ts|
      ts.map {|t| t.value }
    }
  end
  module_function :pipeline

  def pipeline_run(cmds, pipeline_opts, child_io, parent_io, &block) # :nodoc:
    if cmds.empty?
      raise ArgumentError, "no commands"
    end

    opts_base = pipeline_opts.dup
    opts_base.delete :in
    opts_base.delete :out

    wait_thrs = []
    r = nil
    cmds.each_with_index {|cmd, i|
      cmd_opts = opts_base.dup
      if String === cmd
        cmd = [cmd]
      else
        cmd_opts.update cmd.pop if Hash === cmd.last
      end
      if i == 0
        if !cmd_opts.include?(:in)
          if pipeline_opts.include?(:in)
            cmd_opts[:in] = pipeline_opts[:in]
          end
        end
      else
        cmd_opts[:in] = r
      end
      if i != cmds.length - 1
        r2, w2 = IO.pipe
        cmd_opts[:out] = w2
      else
        if !cmd_opts.include?(:out)
          if pipeline_opts.include?(:out)
            cmd_opts[:out] = pipeline_opts[:out]
          end
        end
      end
      pid = spawn(*cmd, cmd_opts)
      wait_thrs << Process.detach(pid)
      r.close if r
      w2.close if w2
      r = r2
    }
    result = parent_io + [wait_thrs]
    child_io.each {|io| io.close }
    if defined? yield
      begin
	return yield(*result)
      ensure
	parent_io.each{|io| io.close unless io.closed?}
        wait_thrs.each {|t| t.join }
      end
    end
    result
  end
  module_function :pipeline_run
  class << self
    private :pipeline_run
  end

end

if $0 == __FILE__
  a = Open3.popen3("nroff -man")
  Thread.start do
    while line = gets
      a[0].print line
    end
    a[0].close
  end
  while line = a[1].gets
    print ":", line
  end
end
