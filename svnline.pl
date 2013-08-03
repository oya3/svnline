#<!-- -*- encoding: utf-8n -*- -->
use strict;
use warnings;
use utf8;

use Cwd;
use Encode;
use Encode::JP;

use File::Path;
use Data::Dumper;

print "svnline ver. 0.13.08.03.\n";
my ($argv, $gOptions) = getOptions(\@ARGV); # オプションを抜き出す
my $args = @{$argv};

if( $args != 2 ){
	print "Usage: svnline [options] <svn address> <output file>\n";
	print "  options : -u : user.\n";
	print "          : -p : password.\n";
	print "          : -r (start:end) : revsion number.\n";
	print "          : -t (file type regexp) : target file type.\n";
	print "          : -xls (fileNmae) : output for excel.\n";
	print "          : -wo (file) : without file path.\n";
    exit;
}

if( !isInstallSVN() ){
	die "svn not installed.";
}

my $fileList = undef;
my $srev = '';
my $erev = '';
my $address = $argv->[0];
my $outputFile = $argv->[1];

# オプション指定でリビジョンが存在か確認
if( exists $gOptions->{'-r_start'} ){
	# オプション指定がある
	$srev = $gOptions->{'-r_start'};
	$erev = $gOptions->{'-r_end'};
}
else{
	# ブランチの最初と最後のリビジョンを取得する
	($srev, $erev, $fileList) = getRevisionNumber($address);
}
# 対象ファイル生成
my $ptn = 'c|h|cpp|hpp|cxx|hxx';
if( defined $gOptions->{'-t'} ){
	$ptn = $gOptions->{'-t'};
}

# 除外パス生成
my $withoutPath = undef;
if( defined $gOptions->{'-wo'} ){
	$withoutPath = getWithoutPath($gOptions->{'-wo'});
}

my $targetFileList=undef;
$targetFileList->{$srev} = getFileList( $address, $srev, $ptn, $withoutPath); # start
$targetFileList->{$erev} = getFileList( $address, $erev, $ptn, $withoutPath); # end

my $analyzeReport = analyzeFileList( $address, $targetFileList, $srev, $erev);
exportFile($outputFile, $analyzeReport);
print "complate.\n";
exit;

sub analyzeFileList
{
	my ( $address, $targetFileList, $srev, $erev) = @_;

	mkdir "tmp";
	svnCmd("export","-r $srev", $address, "tmp\/$srev");
	svnCmd("export","-r $erev", $address, "tmp\/$erev");
	
	my %outFileList = ();
	$outFileList{'srev'} = $srev;
	$outFileList{'erev'} = $erev;
	while( my ($rev, $fileList) = each %{$targetFileList}){
		foreach my $file (@{$fileList}){
			#print encode('cp932', "[tmp\/$rev\/$file]\n");
			
			my $file_sjis = encode('cp932', "tmp\/$rev\/$file");
			open (IN, "<$file_sjis") or die "[$file_sjis]$!";
			my @array = <IN> ;
			close IN;
			unlink $file_sjis;

			my ($total,$withoutCommentTotal) = getLineForCPP(\@array);
			my $fileCount = \%{$outFileList{'file'}{$rev}{$file}};
			$fileCount->{'total'} = $total;
			$fileCount->{'withoutCommentTotal'} = $withoutCommentTotal;
			#print encode('cp932', "<analyzeFileList>[$total][$withoutCommentTotal]$file\[$fileCount->{'total'}\]\[$fileCount->{'withoutCommentTotal'}\]\n");
		}
	}
	File::Path::rmtree("tmp") or die "[tmp]$!";
	
	return \%outFileList;
}

sub getLineForCPP
{
	my ($array) = @_;
	
	my $total = @{$array}; # トータル行数
	my $sourceString = decode('cp932', join '', @{$array});
	$sourceString =~ s#/\*[^*]*\*+([^/*][^*]*\*+)*/|//[^\n]*|("(\\.|[^"\\])*"|'(\\.|[^'\\])*'|.[^/"'\\]*)#defined $2 ? $2 : ""#gse;
	my @sourceWithoutCommnet = split /\n/, $sourceString;
	my @source = ();
	foreach my $line (@sourceWithoutCommnet){
		if( $line =~ /^\s*$/ ){ # 空行は削除
			next;
		}
		push @source,$line;
	}
	#	print encode('cp932', join "\n",@source);
	my $withoutTotal = @source; # コメント除去行数
	return ($total, $withoutTotal);
}

sub exportFile
{
	my ($file,$analyzeReport) = @_;

	my $srev = $analyzeReport->{'srev'};
	my $erev = $analyzeReport->{'erev'};

	my %out = ();
	while( my ($file, $param) = each %{$analyzeReport->{'file'}{$srev}}){
		$out{$file}{'s_total'} = $param->{'total'};
		$out{$file}{'s_withoutCommentTotal'} = $param->{'withoutCommentTotal'};
		$out{$file}{'e_total'} = 0;
		$out{$file}{'e_withoutCommentTotal'} = 0;
		#print encode('cp932', "<exportFile start>[$srev]$file\[$out{$file}{'s_total'}\]\[$out{$file}{'s_withoutCommentTotal'}\]\n");
	}
	while( my ($file, $param) = each %{$analyzeReport->{'file'}{$erev}}){
		$out{$file}{'e_total'} = $param->{'total'};
		$out{$file}{'e_withoutCommentTotal'} = $param->{'withoutCommentTotal'};
		if( !defined $out{$file}{'s_total'} ){
			$out{$file}{'s_total'} = 0;
			$out{$file}{'s_withoutCommentTotal'} = 0;
		}
		#print encode('cp932', "<exportFile end>[$erev]$file\[$out{$file}{'e_total'}\]\[$out{$file}{'e_withoutCommentTotal'}\]\n");
	}
	my $file_sjis = encode('cp932', $file);
	
	open (OUT, ">$file_sjis") or die "[$file_sjis]$!";
	print OUT encode('cp932', ",全行数,,,,,コメント除去後行数,,,,\n");
	print OUT encode('cp932', "ファイル名,rev.$srev,rev.$erev,流用,追加,削除,rev.$srev,rev\.$erev,流用,追加,削除\n");
	foreach my $file ( sort keys %out ){
		my $param = \%{$out{$file}};
		my ($diversion, $add, $del)   = getModifiedLine($param->{'s_total'}, $param->{'e_total'});
		my ($wdiversion, $wadd, $wdel) = getModifiedLine($param->{'s_withoutCommentTotal'}, $param->{'e_withoutCommentTotal'});
		my $line = encode('cp932', "$file,$param->{'s_total'},$param->{'e_total'},$diversion,$add,$del,$param->{'s_withoutCommentTotal'},$param->{'e_withoutCommentTotal'},$wdiversion,$wadd,$wdel\n");
		print OUT $line;
	}
	close OUT;
}

sub getModifiedLine
{
	my ($startLine, $endLine) = @_;
	#print "lines[$startLine\/$endLine]\n";
	my $mod = $endLine - $startLine;
	my $diversion =0; my $add = 0; my $del = 0;
	if( $mod >= 0 ){
		$add = $mod;
		$diversion = $startLine;
	}
	else{
		$del =abs($mod);
		$diversion = $endLine;
	}
	return ($diversion, $add, $del);
}

sub getWithoutPath
{
	my ($file) = @_;
	my $file_sjis = encode('cp932', $file);
	open (IN, "<$file_sjis") or die "[$file_sjis]$!";
	my @array = <IN> ;
	close IN;
	my @out = ();
	foreach my $path (@array){
		$path = decode('cp932', $path);
		chomp $path;
		push @out, $path;
	}
	return \@out;
}

sub getFileList
{
	my ($address, $rev, $ptn, $withoutPath) = @_;
	
	my $lists = svnCmd("list","--recursive -r $rev", $address, "");

	my @out = ();
	foreach my $fileName (@{$lists}){
		chomp $fileName;
		if( $fileName =~ /.+?\/$/ ){ # フォルダは無視
			next;
		}
		if( $fileName =~ /.+?\.($ptn)$/ ){ # 対象ファイルのみ抽出
			if( defined $withoutPath ){
				my $i = 0;
				for(;$i<@{$withoutPath};$i++){
					if( $fileName =~/$withoutPath->[$i]/ ){
						# 除外パス該当
						last;
					}
				}
				if( $i != @{$withoutPath} ){
					# 除外パス
					next;
				}
			}
			chomp $fileName;
			push @out, $fileName;
			#print encode('cp932', "<getFileList>$fileName\n");
		}
	}
	return \@out;
}

sub execCmd
{
	my ($cmd) = @_;
	$cmd = encode('cp932', $cmd);
	print "cmd : $cmd\n";
	open my $rs, "$cmd 2>&1 |";
	my @rlist = <$rs>;
	my @out = ();
	foreach my $line (@rlist){
		push @out, decode('cp932', $line);
	}
	close $rs;
	return \@out;
#	return \@rlist;
}

sub execCmd2
{
	my ($cmd) = @_;
	print encode('cp932', "cmd : $cmd\n");
	my $res = `$cmd 2>&1`;
	my @array = split /\n/,$res;
	print @array;
	return \@array;
}

# svn cmd [option] addres [args...]
sub svnCmd
{
	my ($cmd, $option, $address, $arg) = @_;
	my $user = getUserInfo();
	my $svnCmd = "svn $cmd $user $option \"$address\" $arg";
	return execCmd($svnCmd);
}

sub getUserInfo
{
	my $res = '';
	if( exists $gOptions->{'-u'} ){
		$res = "--username $gOptions->{'-u'}";
	}
	if( exists $gOptions->{'-p'} ){
		$res = $res." --password  $gOptions->{'-p'}";
	}
	return $res;
}

sub isInstallSVN
{
	my $res = execCmd('svn');
	if( $res->[0] =~ /svn help/ ){
		return 1;
	}
	return 0;
}

sub getDiffFileList
{
	my ($array) = @_;
	my @files = ();
	foreach my $line (@{$array}){
		if( $line =~ /^Index: (.+?)$/ ){
			push @files, $1;
		}
	}
	return \@files;
}

# ブランチの最初と最後のリビジョンを取得する
sub getRevisionNumber
{
	my ($address) = @_;
	# --stop-on-copy を指定するとブランチができたポイントまでとなる
	# --verbose を指定すると追加／削除／変更がファイル単位で分かる
	my $resArray = svnCmd("log", "--stop-on-copy --verbose", "$address", "");
	
	my @revs = ();
	my %fileList = ();
	while( my $line = pop(@{$resArray}) ){ # 過去からさかのぼる
		# exe : r1993 | k-oya | 2013-07-22 22:24:36 +0900 (月, 22 7 2013) | 3 lines
		if( $line =~ /^r([0-9]+) |.+ lines$/ ){
#			print "rev[$1]\n";
			push @revs, $1;
		}
		elsif( $line =~ /^   ([MADR]{1}) (\/.+?)$/ ){
			my $a1 = $1; my $a2 = $2;
			if( $a2 =~ /\(from .+\)/ ){
				next; # フォルダなんでfilelistの対象としない
			}
			# A 項目が追加されました。
			# D 項目が削除されました。
			# M 項目の属性やテキスト内容が変更されました。
			# R 項目が同じ場所の違うもので置き換えられました。
			if( exists $fileList{$a2} ){
				if( $a1 =~ /^[AD]$/ ){
					$fileList{$a2} = $a1;
				}
			}
			else{
				$fileList{$a2} = $a1;
			}
			
		}
	}
	return ($revs[0], $revs[$#revs], \%fileList);
}


sub getOptions
{
	my ($argv) = @_;
	my %options = ();
	my @newAragv = ();
	for(my $i=0; $i< @{$argv}; $i++){
		my $key = decode('cp932', $argv->[$i]); # 入力アーギュメントは文字コードを変更してやらないとダメっぽい。
		if( $key eq '-r' ){ # key = value(param:param)
			my $param = decode('cp932', $argv->[$i+1]);
			if( $param !~ /^(%d):(%d)$/ ) {
				die "illigal parameter with options ($param)";
			}
			$options{'-r_start'} = $1;
			$options{'-r_end'} = $2;
			$i++;
		}
		elsif( $key =~ /^-(u|p|t|xls|wo)$/ ){ # key = value;
			$options{$key} = decode('cp932', $argv->[$i+1]);
			$i++;
		}
		else{
			push @newAragv, $key;
		}
	}
	return (\@newAragv, \%options);
}

