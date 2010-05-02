use strict;
use warnings;
use 5.010;
use autodie;
binmode STDOUT, ':encoding(UTF-8)';
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

my $in_file = $ARGV[0] // 'talk';
my $text = do {
    open my $f, '<:encoding(UTF-8)', $in_file;
    local $/;
    <$f>;
};

my $page_num = 1;
my @blocks = grep { $_ } split /^= /m, $text;
my @titles = ('Index');
for my $block (@blocks) {

    my $prev = sprintf '%04d.html',     $page_num - 1;
    my $fn   = sprintf 'out/%04d.html', $page_num;

    my ($title, $body) = split /\n/, $block, 2;
    say "$page_num $title";
    $title =~ s/\s*$//;
    $titles[$page_num] = $title;
    my $t = template();
    $t->param(
        normal_page    => 1,
        title => $title,
        first => '0000.html',
        last  => sprintf('%04d.html', scalar(@blocks)),
        next  => sprintf('%04d.html', min scalar(@blocks), $page_num + 1),
        prev  => sprintf('%04d.html', $page_num - 1),
        page_num    => $page_num,
        total_page_count => scalar(@blocks),
    );
    if ($body =~ /^:(\w+)/) {
        my $type = $1;
        $body =~ s/^:\w+\h*\n//;
        say "slide type: $type";
        if ($type eq 'raw') {
            $t->param(contents => $body);
        } else {
            $t->param(contents => "<pre>" . hilight($type, $body) . "</pre>");
        }
    } else {
        my $star_count =()= $body =~ /^\s*\*/mg;
        if ($star_count >= 2) {
            $t->param(contents => render_list($body));
        } else {
            die "Don't know how to render slide $page_num";
        }
    }
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
    open my $out_fh, '>:encoding(UTF-8)', 'out/0000.html';
    print $out_fh $t->output;
    close $out_fh;
}

sub hilight {
    my ($type, $text) = @_;
    my $cachekey = md5("$type|$text");
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
