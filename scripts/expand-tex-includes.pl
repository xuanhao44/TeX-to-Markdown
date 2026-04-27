use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Spec;

my $entry = shift @ARGV or die "expand_tex_includes: source file required\n";
$entry = abs_path($entry) or die "expand_tex_includes: cannot resolve '$entry'\n";

my %stack;

sub resolve_include_path {
  my ($base_dir, $target) = @_;
  $target =~ s/^\s+|\s+$//g;
  return if $target eq '';
  return if $target =~ m{^/};
  return if $target =~ /^[A-Za-z]:[\\\/]/;

  my @candidates = ($target);
  push @candidates, "$target.tex" unless $target =~ /\.[^\/]+$/;

  for my $candidate (@candidates) {
    my $path = File::Spec->catfile($base_dir, $candidate);
    my $resolved = abs_path($path);
    return $resolved if defined $resolved && -f $resolved;
  }

  return;
}

sub expand_file {
  my ($path) = @_;
  die "expand_tex_includes: include cycle detected at '$path'\n" if $stack{$path};
  local $stack{$path} = 1;

  open my $fh, '<', $path or die "expand_tex_includes: cannot open '$path': $!\n";
  my $base_dir = dirname($path);
  my $output = '';

  while (my $line = <$fh>) {
    my $cursor = 0;
    my $expanded_line = '';

    while ($line =~ /\\(input|include)\{([^}]+)\}/g) {
      my $match_start = $-[0];
      my $match_end = $+[0];
      my $target = $2;

      $expanded_line .= substr($line, $cursor, $match_start - $cursor);

      my $resolved = resolve_include_path($base_dir, $target);
      if (defined $resolved) {
        $expanded_line .= "\n" . expand_file($resolved) . "\n";
      } else {
        $expanded_line .= substr($line, $match_start, $match_end - $match_start);
      }

      $cursor = $match_end;
    }

    $expanded_line .= substr($line, $cursor);
    $output .= $expanded_line;
  }

  close $fh;
  return $output;
}

print expand_file($entry);
