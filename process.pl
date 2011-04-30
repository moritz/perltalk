#!/usr/bin/env perl
use strict;
use warnings;
use 5.010;
use autodie;
binmode STDOUT, ':encoding(UTF-8)';
use utf8;
use HTML::Template::Compiled;
use Text::VimColor;
use Cache::FileCache;
use Digest::MD5 qw(md5);
use List::Util qw(min max);
my $cache = Cache::FileCache->new();
use Encode qw(encode_utf8 decode_utf8);

sub template {
    HTML::Template::Compiled->new(
        filename        => 'template.tmpl',
        tagstyle        => [qw/+asp_chomp/],
        open_mode       => ':utf8',
        default_escape  => 'html',
    );
}

my $s5 = HTML::Template::Compiled->new(
    filename        => 's5.tmpl',
    tagstyle        => [qw/+asp_chomp/],
    open_mode       => ':utf8',
    default_escape  => 'html',
);
my @s5_slides;

my $in_file = $ARGV[0] // 'talk';
my $text = do {
    open my $f, '<:encoding(UTF-8)', $in_file;
    local $/;
    <$f>;
};

if ($text =~ /^-----/m) {
    my $header;
    ($header, $text) = split /^-----+\s*/m, $text, 2;
    my @lines = grep length($_), split /\n+/, $header;
    my %h = map { split /\s*:\s*/, $_, 2 } @lines;

    $s5->param(
        global_title    => $h{title},
        global_subtitle => $h{subtitle},
        author          => $h{author},
        affiliation     => $h{affiliation},
    );
} else {
    warn "No header!\n";
}

my $page_num = 1;
my @blocks = grep { $_ } split /^= /m, $text;
my @titles = ('Index');

my $out_dir = 'out-' . $in_file;
mkdir $out_dir unless -d $out_dir;

for my $block (@blocks) {

    my $prev = sprintf '%04d.html',     $page_num - 1;
    my $fn   = sprintf '%s/%04d.html',  $out_dir, $page_num;

    my ($title, $body) = split /\n/, $block, 2;
    say "$page_num $title";
    $title =~ s/\s*$//;
    $titles[$page_num] = $title;
    my $t = template();
    $t->param(
        normal_page    => 1,
        title => $title,
        first => sprintf('%04d.html', 0),
        last  => sprintf('%04d.html', scalar(@blocks)),
        next  => sprintf('%04d.html', min scalar(@blocks), $page_num + 1),
        prev  => sprintf('%04d.html', $page_num - 1),
        page_num    => $page_num,
        total_page_count => scalar(@blocks),
    );
    my $contents;
    if ($body =~ /^:(\w+)/) {
        my $type = $1;
        $body =~ s/^:\w+\h*\n//;
        say "slide type: $type";
        if ($type eq 'raw') {
            $contents = $body;
        } else {
            $contents =  "<pre>" . hilight($type, $body) . "</pre>";
        }
    } else {
        my $star_count =()= $body =~ /^\s*\*/mg;
        if ($star_count >= 2) {
           $contents = render_list($body);
        } else {
            die "Don't know how to render slide $page_num with title '$title'";
        }
    }
    $t->param(contents => $contents);
    push @s5_slides, { contents => $contents, title => $title, page => $page_num };
    open my $out_fh, '>:encoding(UTF-8)', $fn;
    print $out_fh $t->output;
    close $out_fh;
} continue {
    $page_num++;
}
$page_num--;

{
    # index page
    my $t = template();
    $t->param(
        title   => 'Index',
        next    => '0001.html',
        prev    => '0000.html',
        first   => '0000.html',
        last    => sprintf('%04d.html', scalar(@blocks)),
    );
    my $c = "<ul>\n";
    for my $i (0..$page_num) {
        $c .= sprintf qq[<li><a href="%04d.html">%s</a></li>\n],
                      $i, escape($titles[$i]);
    }
    $c .= "</ul>\n";
    $t->param(contents => $c);
#    unshift @s5_slides, { title => 'Index', contents => $c };
    open my $out_fh, '>:encoding(UTF-8)', 'out/0000.html';
    print $out_fh $t->output;
    close $out_fh;
}
$s5->param('slides' => \@s5_slides);

{
    open my $s5_out, '>:encoding(UTF-8)', 's5/index.html';
    print { $s5_out } $s5->output;
    close $s5_out;
}

sub hilight {
    my ($type, $text) = @_;
    my $cachekey = md5(encode_utf8 "$type|$text");
    my $c = $cache->get($cachekey);
    return $c if defined $c;


    my @lines = split /\n/, $text;
    my $min_ws = 999_999;
    for (@lines) {
        next if $_ =~ /^\s*$/;
        /^(\s*)/;
        if (length($1) < $min_ws) {
            $min_ws = length($1);
        }
    }
    if ($min_ws > 0) {
        substr($_, 0, $min_ws) = '' for @lines;
        $text = join "\n", @lines;
    }

    my $s = Text::VimColor->new(
        filetype    => $type,
        string      => encode_utf8($text),
    );
    $s = decode_utf8($s->html);
    $cache->set($cachekey, $s);
    return $s;

}

sub render_list {
    my $block = shift;
    my @lines = grep { $_ } split /^\s*\*/m, $block;
    s/^\*\s*//g for @lines;
    my $processed = "<ul>\n";
    for (@lines) {
        chomp;
        $processed .= '    <li>' . markup($_) . "</li>\n";
    }
    $processed .= "</ul>\n";
    return $processed;
}

sub markup {
    my $str = shift;
    $str = ' ' . $str;
    my @tokens = split /`/, $str;
    for my $i (0..$#tokens) {
        $tokens[$i] = escape($tokens[$i]);
        if ($i % 2) {
            $tokens[$i] = "<code>$tokens[$i]</code>";
        }
    }
    join '', @tokens;
}

sub escape {
    my $s = shift;
    my %escapes = (
        '&' =>  '&amp;',
        '"' =>  '&quot;',
        '<' =>  '&lt;',
        '>' =>  '&gt;',
    );
    $s =~ s/([&"<>])/$escapes{$1}/g;
    return $s;
}
