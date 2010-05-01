use strict;
use warnings;
use 5.010;
use autodie;
binmode STDOUT, ':encoding(UTF-8)';
use HTML::Template::Compiled;
use Text::VimColor;
use Cache::FileCache;
use Digest::MD5 qw(md5);
my $cache = Cache::FileCache->new();

my $in_file = $ARGV[0] // 'talk';
my $text = do {
    open my $f, '<:encoding(UTF-8)', $in_file;
    local $/;
    <$f>;
};

my $page_num = 1;
my @blocks = grep { $_ } split /^= /m, $text;
for my $block (@blocks) {

    my $prev = sprintf '%04d.html',     $page_num - 1;
    my $fn   = sprintf 'out/%04d.html', $page_num;
    my $next = sprintf '%04d.html',     $page_num + 1;

    my ($title, $body) = split /\n/, $block, 2;
    $title =~ s/\s*$//;
    say $title;
    my $t = HTML::Template::Compiled->new(
        filename        => 'template.tmpl',
        tagstyle        => [qw/+asp_chomp/],
        open_mode       => ':utf8',
        default_escape  => 'html',
    );
    $t->param(title => $title, next => $next, prev => $prev);
    if ($body =~ /^:(\w+)/) {
        my $type = $1;
        $body =~ s/^:\w+\h*\n//;
        say "slide type: $type";
        $t->param(contents => "<pre>" . hilight($type, $body) . "</pre>");
    } else {
        my $star_count =()= $body =~ /^\s*\*/mg;
        if ($star_count >= 2) {
            $t->param(contents => render_list($body));
        } else {
            die "Don't know how to render slide $page_num";
        }
    }
    say $t->output;
    open my $out_fh, '>:encoding(UTF-8)', $fn;
    print $out_fh $t->output;
    close $out_fh;
} continue {
    $page_num++;
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
        string      => $text,
    );
    $s = $s->html;
    $cache->set($cachekey, $s);
    return $s;

}

sub render_list {
    my $block = shift;
    $block =~ s/^.*\n$//mg;
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
