use strict;
use warnings;
use Test::More;

$ENV{TOADFARM_SILENT} = 1;
$ENV{HOME} = 't';

plan skip_all => 'Cannot run on Win32' if $^O =~ /win/i;
plan skip_all => 'Cannot read t/.toadfarm/script.conf' unless -r 't/.toadfarm/script.conf';

my(@exec, $ret);
*CORE::GLOBAL::exec = sub { @exec = @_; $ENV{STAY_ALIVE} or die 'exec' };
*CORE::GLOBAL::exit = sub { die 'exit' };

{
  local $ENV{MOJO_APP_LOADER} = 1;
  $ret = do 'script/toadfarm';
  isa_ok $ret, 'Mojolicious';
}

{
  local @ARGV = qw( a b c --man d e --start );
  do 'script/toadfarm';
  like $@, qr{exec}, 'exec perldoc';
  is_deeply \@exec, [ perldoc => 'Toadfarm' ], 'perldoc Toadfarm';
}

{
  local @ARGV = qw( script.conf );
  do 'script/toadfarm';
  like $@, qr{exec}, 'exec hypnotoad';
  is_deeply \@exec, [ hypnotoad => 'script/toadfarm' ], 'hypnotoad script/toadfarm';
  like $ENV{MOJO_CONFIG}, qr{t/\.toadfarm/script\.conf$}, 'MOJO_CONFIG';

  local @ARGV = qw( t/.toadfarm/script.conf -a );
  do 'script/toadfarm';
  like $@, qr{ -a }, 'require app with -a';

  local $ENV{PATH} = '/bin:script:/foo';
  local @ARGV = qw( t/.toadfarm/script.conf -a toadfarm );
  do 'script/toadfarm';
  is_deeply \@exec, [ hypnotoad => 'script/toadfarm' ], 'hypnotoad script/toadfarm';

  local @ARGV = qw( t/.toadfarm/script.conf -a script/toadfarm --stop );
  do 'script/toadfarm';
  is_deeply \@exec, [ hypnotoad => '--stop' => 'script/toadfarm' ], 'hypnotoad --stop';
}

{
  local $ENV{STAY_ALIVE} = 1;
  local @ARGV = qw( script.conf -a script/toadfarm --start );
  do 'script/toadfarm';
  like $@, qr{exit}, 'exit start()';
  is_deeply \@exec, [ hypnotoad => 'script/toadfarm' ], 'toadfarm --start';

  open my $PID, '>', '/tmp/t-t-toadfarm-test.pid' or die $!;
  print $PID $$;
  close $PID;
  @exec = ();
  local @ARGV = qw( script.conf -a script/toadfarm --start );
  do 'script/toadfarm';
  like $@, qr{exit}, 'exit start()';
  is_deeply \@exec, [], 'already running';
}

{
  delete $ENV{MOJO_CONFIG};
  local $ENV{PATH} = '/bin:script:/foo';
  local @ARGV = qw( -a t/app.pl );
  chmod 0755, 't/app.pl';
  do 'script/toadfarm';
  is_deeply \@exec, [ hypnotoad => 't/app.pl' ], 'hypnotoad with just -a';
  like $ENV{MOJO_CONFIG}, qr{/t/\.toadfarm/app\.pl\.conf}, 'MOJO_CONFIG from -a';
  is $ENV{TOADFARM_APPLICATION_CLASS}, 'Toadfarm', 'default TOADFARM_APPLICATION_CLASS';
}

{
  delete $ENV{MOJO_CONFIG};
  local @ARGV = qw( -a t::App );
  do 'script/toadfarm';
  is_deeply \@exec, [ hypnotoad => 'script/toadfarm' ], 'hypnotoad with application class';
  is $ENV{TOADFARM_APPLICATION_CLASS}, 't::App', 'custom TOADFARM_APPLICATION_CLASS';
  like $ENV{MOJO_CONFIG}, qr{/t/\.toadfarm/t-app\.conf}, 'MOJO_CONFIG from TOADFARM_APPLICATION_CLASS';
}

done_testing;
