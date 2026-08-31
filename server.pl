#!/usr/bin/env perl
use strict;
use warnings;

use Cwd qw(abs_path);
use File::Spec;
use IO::Socket::INET;

sub uri_unescape {
    my ($value) = @_;
    $value =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    $value =~ tr/+/ /;
    return $value;
}

my $port = 5000;
my $root = abs_path('.');

my %content_types = (
    html => 'text/html; charset=UTF-8',
    css  => 'text/css; charset=UTF-8',
    js   => 'text/javascript; charset=UTF-8',
    json => 'application/json; charset=UTF-8',
    png  => 'image/png',
    jpg  => 'image/jpeg',
    jpeg => 'image/jpeg',
    svg  => 'image/svg+xml',
    ico  => 'image/x-icon',
);

my $server = IO::Socket::INET->new(
    LocalAddr => '0.0.0.0',
    LocalPort => $port,
    Proto     => 'tcp',
    Listen    => 10,
    ReuseAddr => 1,
) or die "Could not start server on port $port: $!";

$server->autoflush(1);
print "Serving $root on http://0.0.0.0:$port\n";

while (my $client = $server->accept()) {
    $client->autoflush(1);

    my $request_line = <$client> // '';
    while (<$client>) {
        last if /^\r?\n$/;
    }

    my ($method, $request_target) = $request_line =~ m{^(\S+)\s+(\S+)\s+HTTP/\S+};
    if (!$method || !$request_target || ($method ne 'GET' && $method ne 'HEAD')) {
        print $client "HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\nContent-Length: 0\r\n\r\n";
        close $client;
        next;
    }

    my ($path) = split /\?/, $request_target, 2;
    $path = uri_unescape($path);
    $path = '/index.html' if $path eq '/' || $path eq '';

    if ($path eq '/favicon.ico') {
        print $client "HTTP/1.1 204 No Content\r\nConnection: close\r\nContent-Length: 0\r\n\r\n";
        close $client;
        next;
    }

    my $relative_path = $path;
    $relative_path =~ s{^/}{};
    my $file = File::Spec->catfile($root, split m{/}, $relative_path);
    my $resolved_file = abs_path($file);

    if (!$resolved_file || index($resolved_file, "$root/") != 0 || !-f $resolved_file) {
        print $client "HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n";
        close $client;
        next;
    }

    open my $handle, '<:raw', $resolved_file
        or do {
            print $client "HTTP/1.1 500 Internal Server Error\r\nConnection: close\r\nContent-Length: 0\r\n\r\n";
            close $client;
            next;
        };

    my $body = do { local $/; <$handle> };
    close $handle;

    my ($extension) = $resolved_file =~ /\.([^.\/]+)$/;
    my $content_type = $content_types{lc($extension // '')} // 'application/octet-stream';
    my $length = length($body);

    print $client "HTTP/1.1 200 OK\r\n";
    print $client "Content-Type: $content_type\r\n";
    print $client "Content-Length: $length\r\n";
    print $client "Cache-Control: no-cache\r\n";
    print $client "Connection: close\r\n\r\n";
    print $client $body unless $method eq 'HEAD';
    close $client;
}