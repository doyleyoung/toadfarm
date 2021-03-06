package Ubic::Service::Toadfarm;

=head1 NAME

Ubic::Service::Toadfarm - Ubic Toadfarm service class

=head1 DESCRIPTION

This class require L<Ubic> which is not automatically installed by
L<Toadfarm>.

=head1 SYNOPSIS

Put the code below in a C<ubic> service file:

  use Ubic::Service::Toadfarm;
  Ubic::Service::Toadfarm->new(
    log => {
      file => '/path/to/log/file', # required
      combined => 1,
    },

    # toadfarm config args
    secret => 'super secret',
    apps => [...],
    plugins => [...],
  );

=head2 Details

=over 4

=item * pid_file

This file is created automatically. It will be stored in the "tmp" directory
in your "ubic" data directory. This means that you do not have to specify the
pid_file in the "hypnotoad" config section.

=item * MOJO_CONFIG

The Toadfarm application will be started with a config file generated by this
service class. The config file will be stored in the "tmp" directory in your
"ubic" data directory.

=back

=head2 Hypnotoad starter

It is possible to use this module as a generic C<hypnotoad> starter, instead
of L<Ubic::Service::Hypnotoad>, by setting the "HYPNOTOAD_APP" environment
variable:

  use Ubic::Service::Toadfarm;
  Ubic::Service::Toadfarm->new(
    env => {
      HYPNOTOAD_APP => '/path/to/my-mojo-app',
    },
  );

=cut

use strict;
use warnings;
use Data::Dumper ();
use File::Basename;
use File::Spec::Functions qw(catfile);
use File::Which qw(which);
use Ubic::Result qw(result);
use Ubic::Settings;
use constant DEBUG => $ENV{UBIC_TOADFARM_DEBUG} || 0;

use parent 'Ubic::Service::Skeleton';

$ENV{HYPNOTOAD_APP} ||= which 'toadfarm';

=head1 METHODS

=head2 new

See L</SYNOPSIS>.

=cut

sub new {
  my $class = shift;
  my $args = @_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {};
  my $self = bless $args, $class;

  ref $self->{hypnotoad}{listen} eq 'ARRAY' or die 'Invalid/missing hypnotoad => listen';

  warn Data::Dumper::Dumper($self) if DEBUG == 2;
  return $self;
}

=head2 start_impl

This is called when you run C<ubic start>. It will start L<toadfarm|Toadfarm>
using L<hypnotoad|Mojo::Server::Hypnotoad> after writing the toadfarm config
and settings L<MOJO_CONFIG>.

The config will be written to the "tmp" directory in ubic's data directory.

=cut

sub start_impl {
  my $self = shift;
  my $hypnotoad = which 'hypnotoad';

  $self->_write_mojo_config;
  local %ENV = $self->_env;
  warn "MOJO_CONFIG=$ENV{MOJO_CONFIG} $hypnotoad $ENV{HYPNOTOAD_APP}\n" if DEBUG;
  system $hypnotoad => $ENV{HYPNOTOAD_APP};
}

=head2 status_impl

This method will issue a HTTP "HEAD /ubic-status" request to the server. The
response is not important, the important thing is that the server responds.

=cut

sub status_impl {
  my $self = shift;
  my $listen = $self->{hypnotoad}{listen}[0];
  my $pid = $self->_read_pid;
  my $resource = $self->{hypnotoad}{status_resource} || "/ubic-status";
  my($tx, %args);

  local %ENV = $self->_env;

  # no need to check if process is not running
  if(!$pid or !kill 0, $pid) {
    return result 'not running';
  }

  require Mojo::UserAgent;
  $args{connect_timeout} = $ENV{MOJO_CONNECT_TIMEOUT} || 2;
  $args{request_timeout} = $ENV{MOJO_REQUEST_TIMEOUT} || 2;

  $listen =~ s!\*!localhost!;
  $tx = Mojo::UserAgent->new(%args)->head($listen .$resource);
  warn $tx->res->code // 'No HTTP code', "\n" if DEBUG;

  if(my $code = $tx->res->code) {
    return result "running", "pid $pid, status $code";
  }
  else {
    return result +($ENV{UBIC_TOADFARM_NO_RESPONSE_STATE} || 'running'), "pid $pid, no response";
  }
}

=head2 stop_impl

This method will kill the server pid found in "pid_file" with "TERM".

=cut

sub stop_impl {
  my $self = shift;
  my $pid = $self->_read_pid;

  warn "pid=$pid\n" if DEBUG;
  return result 'not running' unless $pid;
  warn "kill TERM $pid\n" if DEBUG;
  return result 'not running' unless kill 'TERM', $pid;
  return result 'stopped';
}

=head2 reload

This method will reload the server pid found in "pid_file" with "USR2".

=cut

sub reload {
  my $self = shift;
  my $pid = $self->_read_pid;

  warn "pid=$pid\n" if DEBUG;
  return result 'not running' unless $pid;
  warn "kill USR2 $pid\n" if DEBUG;
  $self->_write_mojo_config;
  return result 'not running' unless kill 'USR2', $pid;
  return result 'reloaded';
}

sub _env {
  my $self = shift;

  # Not really sure how to make this work from within a mojo app
  # without clearing these environment variables.

  return(
    %ENV,
    %{ $self->{env} || {} },
    HYPNOTOAD_EXE => '',
    HYPNOTOAD_FOREGROUND => 0,
    HYPNOTOAD_REV => 0,
    HYPNOTOAD_STOP => 0,
    HYPNOTOAD_TEST => 0,
    MOJO_CONFIG => $self->_path_to_mojo_config,
    MOJO_REVERSE_PROXY => $self->{hypnotoad}{proxy} || 0,
  );
}

sub _path_to_mojo_config {
  catfile(Ubic::Settings->data_dir, 'tmp', $_[0]->full_name .'.conf');
}

sub _path_to_pid_file {
  catfile(Ubic::Settings->data_dir, 'tmp', $_[0]->full_name .'.pid');
}

sub _read_pid {
  my $self = shift;
  my $pid_file = $self->{hypnotoad}{pid_file} || $self->_path_to_pid_file;

  return 0 unless -e $pid_file;
  return eval {
    open my $PID, $pid_file or die "Could not read $pid_file: $!";
    scalar(<$PID>) =~ /(\d+)/g ? $1 : 0;
  };
}

sub _write_mojo_config {
  my $self = shift;
  my $data_dir = Ubic::Settings->data_dir;
  my $file = $self->_path_to_mojo_config;
  my %config = %$self;
  my $dumper = Data::Dumper->new([\%config]);

  $config{hypnotoad}{pid_file} ||= $self->_path_to_pid_file;

  open my $CONFIG, '>', $file or die "Could not write $file: $!";
  print $CONFIG $dumper->Indent(1)->Sortkeys(1)->Terse(1)->Deepcopy(1)->Dump;
  close $CONFIG or die "Could not write $file: $!";
}

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

1;
