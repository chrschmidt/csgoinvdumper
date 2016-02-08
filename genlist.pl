#!/usr/bin/perl

use strict;
use warnings;
use HTTP::Message;
use HTTP::Request::Common qw(GET);
use LWP::UserAgent;
# Install JSON::XS for this
use JSON;
use utf8;
use Data::Dumper;

# The name of the file containing the localization, e.g. the displayed named.
# Found in SteamLibrary/steamapps/common/Counter-Strike Global Offensive/csgo/resource/
my $localization_fn = "csgo_english.txt";
# The CS:GO item list to translate numbers from the inventory into strings.
# Found in SteamLibrary/steamapps/common/Counter-Strike Global Offensive/csgo/scripts/items/
my $game_items_fn   = "items_game.txt";
# Request API key from https://steamcommunity.com/dev/apikey and insert your key below
my $api_key         = "<your key here>";
# The API isn't quite stable
my $max_retry_count = 1000;
# But there's no point in hammering and increasing the problem
my $retry_delay     = 5;
# Extra Output
my $debug           = 0;

die "Usage: $0 steamid64\n" unless (@ARGV == 1);
my $steamid64 = pop @ARGV;

my $ua = LWP::UserAgent->new();

my %skin_overrides = (
    410 => "Damascus Steel Normal",
    411 => "Damascus Steel 90° Rotated",

    415 => "Doppler Ruby",
    416 => "Doppler Sapphire",
    417 => "Doppler Black Pearl",
    418 => "Doppler Phase 1",
    419 => "Doppler Phase 2",
    420 => "Doppler Phase 3",
    421 => "Doppler Phase 4"
);

my %weapons = map {$_ => 1} ('C4', 'Grenade', 'Knife', 'Machinegun', 'Pistol',
                             'Rifle', 'Shotgun', 'SMG', 'Sniper Rifle');

binmode (STDOUT, ":utf8");

if (!($steamid64 =~ m/^76561[0-9]{12}$/)) {
    print "$steamid64 doesn't look like a steamid64, resolving...";
    my $request = HTTP::Request->new ("GET", "http://api.steampowered.com/ISteamUser/ResolveVanityURL/v0001/?key=$api_key&vanityurl=$steamid64");
    $request->header ('Accept-Encoding' => scalar HTTP::Message::decodable(), 'Accept' => 'application/json');
    my $result = $ua->request ($request);
    die "Error " . $result->code . " (" . $result->message . ") " if ($result->code != 200);
    $result = decode_json ($result->decoded_content());
    $steamid64 = ${$$result{response}}{steamid};
    $| = 1;
    die "\ntranslation failed" if (!$steamid64);
    die "\ntranslation failed, $steamid64 still doesn't look like a steamid64" if (!($steamid64 =~ m/^7656119[0-9]{10}$/));
    $| = 0;
    print " $steamid64\n";
}

my %locs;
my $F = undef;
open ($F, "<:encoding(UTF-16)", $localization_fn) or die "$!";
while (<$F>) {
    $locs{uc $1} = $2
        if ($_ =~ m/^\s*"([^"]+)"\s*"([^"]+)"\s*$/);
}
close ($F);

# Load item information.
my @stack;
my $storage = {};

sub add_entry {
    my $entry = $storage;
    foreach (@stack) {
        $$entry{$_} = {} if (!exists $$entry{$_});
        $entry = $$entry{$_};
    }
    $$entry{$1} = [] if (!exists $$entry{$1});
    push @{$$entry{$1}}, $2;
}

=pod
# instead of using the ingame reference file, could use the data retrieved from
# http://api.steampowered.com/IEconItems_730/GetSchema/v2/?key=$api_key
# However, this changes the whole icon economy parsing, and seems not to contain everything this needs
do {
    my $request = HTTP::Request->new ("GET", "http://api.steampowered.com/IEconItems_730/GetSchema/v2/?key=$api_key");
    $request->header ('Accept-Encoding' => scalar HTTP::Message::decodable());
    my $result = $ua->request ($request);
    die "Error " . $result->code . " (" . $result->message . ")\n" if ($result->code != 200);
    my $storage2 = decode_json ($result->decoded_content());
    print Dumper $storage2;
} while (0);
=cut

open ($F, "<:encoding(UTF-8):crlf", $game_items_fn) or die "$!";
while (<$F>) {
    my $line = $_;
    if ($line =~ m/^\s*"([^"]+)"\s*$/) {
        push @stack, $1;
    } elsif ($line =~ m/\s*}\s*$/) {
        pop @stack;
    } elsif ($line =~ m/^\s*"([^"]+)"\s+"([^"]+)"\s*$/) {
        add_entry ($1, $2);
    }
}
close ($F);

# Extract recurring information for later use: rarities, items, skins ("paint kits"), music kits, stickers
my (%items, %skins, %musickits, %stickers, %rarities, %qualities, %weap_rarities);
my $tmp = ${$$storage{items_game}}{rarities};
foreach (keys %$tmp) {
    my $item = $$tmp{$_};
    $rarities{$_} = $locs{uc @{$$item{loc_key}}[0]};
    $rarities{@{$$item{value}}[0]} = $rarities{$_};
    $weap_rarities{$_} = $locs{uc @{$$item{loc_key_weapon}}[0]};
    $weap_rarities{@{$$item{value}}[0]} = $weap_rarities{$_};
}
$tmp = ${$$storage{items_game}}{qualities};
$qualities{$$tmp{$_}{value}[0]} = $locs{uc $_} foreach (keys %$tmp);

$tmp = ${$$storage{items_game}}{paint_kits};
foreach (keys %$tmp) {
    $skins{$_} = $locs{uc $$tmp{$_}{description_tag}[0] =~ s/^#//r}
        if (defined $$tmp{$_}{description_tag}[0]);
}
$tmp = ${$$storage{items_game}}{music_definitions};
$musickits{$_} = $locs{uc $$tmp{$_}{loc_name}[0] =~ s/^#//r} foreach (keys %$tmp);
$musickits{$$tmp{$_}{name}[0]} = $locs{uc $$tmp{$_}{loc_name}[0] =~ s/^#//r} foreach (keys %$tmp);
$tmp = ${$$storage{items_game}}{sticker_kits};
$stickers{$_} = $locs{uc $$tmp{$_}{item_name}[0] =~ s/^#//r} foreach (keys %$tmp);
$stickers{$$tmp{$_}{name}[0]} = $locs{uc $$tmp{$_}{item_name}[0] =~ s/^#//r} foreach (keys %$tmp);

sub get_name {
    my ($item) = @_;
    my $prefab = ${${$$storage{items_game}}{prefabs}}{@{$$item{prefab}}[0] =~ s/^valve //r};
    if (exists $$item{item_name}) { return @{$$item{item_name}}[0]; }
    elsif (exists $$prefab{item_name}) { return @{$$prefab{item_name}}[0]; }
    else { die "Nothing found for $_ @{$$item{name}}[0]"; }
}

$tmp = ${$$storage{items_game}}{items};
foreach (keys %$tmp) {
    my $item = $$tmp{$_};
    next if (exists $$item{hidden});
    my $prefab = ${${$$storage{items_game}}{prefabs}}{@{$$item{prefab}}[0] =~ s/^valve //r};
    my $name = get_name ($item);
    my $class;
    do {
        if (exists $$item{item_type_name}) { $class = @{$$item{item_type_name}}[0]; }
        elsif (exists $$prefab{item_type_name}) { $class = @{$$prefab{item_type_name}}[0]; }
        elsif (exists $$prefab{prefab}) { $prefab = ${${$$storage{items_game}}{prefabs}}{@{$$prefab{prefab}}[0]}; }
        else { die "No class found for $_ $name"; }
    } while (!$class);
    $name = $locs{uc $name =~ s/^#//r};
    if ($$item{loot_list_name}) {
        my $lootlist = ${$$storage{items_game}}{client_loot_lists}{$$item{loot_list_name}[0]};
        if ($$lootlist{public_list_contents}) {
            my ($iname, $content);
            foreach (keys %$lootlist) { $content = $_ if ($_ ne "public_list_contents") };
            ($iname, $content) = ($1, $2) if ($content =~ m/\[([^]]+)\](.+)/);
            foreach (keys %$tmp) {
                $name = "$name | " . $locs{uc get_name ($$tmp{$_}) =~ s/^#//r} if ($$tmp{$_}{name}[0] eq $content);
            }
            if ($content eq "sticker") { $name = "$name | $stickers{$iname}" }
            elsif ($content eq "musickit") { $name = "$name | $musickits{$iname}" }
        }
    }
    $items{$_} = { name => $name, class => $locs{uc $class =~ s/^#//r} };
}

my $request = HTTP::Request->new ("GET", "http://api.steampowered.com/IEconItems_730/GetPlayerItems/v0001/?key=$api_key&SteamID=$steamid64");
$request->header ('Accept-Encoding' => scalar HTTP::Message::decodable(), 'Accept' => 'application/json');
my $result;
my $retries = 0;
do {
    $result = $ua->request ($request);
    if ($result->code != 200) {
        print "Error " . $result->code . " (" . $result->message . ")\n";
        die "Retry limit reached" if (++$retries == $max_retry_count);
        sleep ($retry_delay);
    }
} while ($result->code != 200);
my $inventory = decode_json ($result->decoded_content());

print Dumper $result->decoded_content() if ($debug);

my %inventory_items;

foreach (@{${$$inventory{result}}{items}}) {
    my $item = $_;
    my @stickers;
    my ($name, $wearname, $skin, $owner_name, $tournament, $rarity, $quality, $class, $musickit, $sortname);
    my ($wear, $stattrak) = (-1, -1);
    $class = ${$items{$$item{defindex}}}{class};
    $rarity = $$item{rarity};
    $quality = $$item{quality};
    foreach (@{$$item{attributes}}) {
        my $defindex = $$_{defindex};
        if ($defindex == 6) {
            $skin = $$_{float_value};
            if (exists $skin_overrides{$skin}) { $skin = $skin_overrides{$skin} }
            else { $skin = $skins{$skin} };
        }
        $wear = $$_{float_value} if ($defindex == 8);
        $stattrak = $$_{value} if ($defindex == 80);
        $owner_name = $$_{value} if ($defindex == 111);
        $stickers[0] = $stickers{$$_{value}} if ($defindex == 113);
        $stickers[1] = $stickers{$$_{value}} if ($defindex == 117);
        $stickers[2] = $stickers{$$_{value}} if ($defindex == 121);
        $stickers[3] = $stickers{$$_{value}} if ($defindex == 125);
        $stickers[4] = $stickers{$$_{value}} if ($defindex == 129);
        $stickers[5] = $stickers{$$_{value}} if ($defindex == 133);
        $tournament = $locs{uc "CSGO_Tournament_Event_NameShort_" . $$_{value}} if ($defindex == 137);
        $musickit = $musickits{$$_{value}} if ($defindex == 166);
    }

    my $is_weapon = $weapons{$class} ? 1 : 0;

    if ($is_weapon) {
        if ($wear >= 0.44)    { $wearname = $locs{uc "SFUI_InvTooltip_Wear_Amount_4"}; }
        elsif ($wear >= 0.37) { $wearname = $locs{uc "SFUI_InvTooltip_Wear_Amount_3"}; }
        elsif ($wear >= 0.15) { $wearname = $locs{uc "SFUI_InvTooltip_Wear_Amount_2"}; }
        elsif ($wear >= 0.07) { $wearname = $locs{uc "SFUI_InvTooltip_Wear_Amount_1"}; }
        else                  { $wearname = $locs{uc "SFUI_InvTooltip_Wear_Amount_0"}; }

        $name  = sprintf ("$wearname (%5.3f) ", $wear) if ($wear > -1);
        # 4 = unique
        $name .= "$qualities{$quality} " if ($quality != 4);
        # Add StatTrak for knives
        $name .= $locs{uc "strange"} . " " if ($stattrak > -1 && $quality == 3);
        $name .= ${$items{$$item{defindex}}}{name};
        $name .= " | $skin" if ($skin);
        $name .= " ($weap_rarities{$rarity} $class)";
        $name  = sprintf "%s (%d kill%s)", $name, $stattrak, $stattrak == 1 ? "" : "s" if ($stattrak > -1);
        $name .= " (renamed to $owner_name)" if ($owner_name);
        if (scalar @stickers) {
            my $count = 0;
            $name .= " (stickers:";
            foreach (@stickers) { $name = sprintf "%s%s $_", $name, $count++ ? "," : "" if ($_); };
            $name .= ")";
        }
        $name .= " ($tournament)" if ($tournament);
        $sortname  = "$class";
        $sortname .= ${$items{$$item{defindex}}}{name};
        $sortname .= "$skin" if ($skin);
        if ($stattrak > -1) { $sortname .= "1"; }
        elsif ($tournament) { $sortname .= "2"; }
        else { $sortname .= "3"; }
        $sortname .= $wear;
        $class = "Weapon";
    } else {
        $name  = ${$items{$$item{defindex}}}{name};
        $name .= " $stickers[0]" if ($stickers[0]);
        $name .= " $musickit" if ($musickit);
        $sortname = $name;
        # 4 = unique
        if ($quality != 4) {
            $name = "$qualities{$quality} $name ($qualities{$quality} $rarities{$rarity} $class)";
        } else {
            $name .= " ($rarities{$rarity} $class)";
        }
        $name .= " ($stattrak MVPs)" if ($stattrak > -1 && $musickit);
    }
    $name =~ s/\s+/ /g;

    if ($inventory_items{$sortname}) { $inventory_items{$sortname}{count}++; }
    else { $inventory_items{$sortname} = { count => 1, class => $class, rarity => $rarity, name => $name }; }
}

# Sort order: Class (alphabetically), Rarity (descending - rarer stuff first), name (alphabetically)
# Sort name generation ensures stattrak first, souvenir next, regular last, and if multiple of the same,
# wear level (numerically) as tie breaker
foreach (sort {$inventory_items{$a}{class} cmp $inventory_items{$b}{class} or
               $inventory_items{$b}{rarity} cmp $inventory_items{$a}{rarity} or
               $a cmp $b}
             keys %inventory_items) {
    print "$inventory_items{$_}{count}x " if ($inventory_items{$_}{count} > 1);
    print "$inventory_items{$_}{name}\n";
}
