#<!-- -*- encoding: utf-8n -*- -->
use strict;
use warnings;
use utf8;

use Cwd;
use Encode;
use Encode::JP;

use File::Path;
use Data::Dumper;

print "svnline ver. 0.13.08.08.\n";
my ($argv, $gOptions) = getOptions(\@ARGV); # オプションを抜き出す
my $args = @{$argv};

if( $args != 2 ){
	print "Usage: svnline [options] <svn address> <output file>\n";
	print "  options : -u (svn user): user.\n";
	print "          : -p (svn password): password.\n";
	print "          : -r (start:end) : revsion number.\n";
	print "          : -t (file type regexp) : target file type.\n";
	print "          : -xls (fileNmae) : output for excel.\n";
	print "          : -wo (file) : without file path.\n";
	print "          : -tmp_not_delete\n";
	print "          : -dbg : debug mode.\n";
	print "https://github.com/oya3/svnline\n";
    exit;
}

{ # current path of this script.
	my $mypath = decode('cp932', __FILE__);
	$mypath =~ s/^(.+)[\\\/].+$/$1/;
	$mypath =~ s/\\/\//g;
	if( $mypath !~ /\// ){
		$mypath = '.';
	}
	$gOptions->{'script_path'} = $mypath;
	dbg_print("script_path : $mypath\n");
}

if( !isInstallSVN() ){
	die "svn not installed.";
}
if( !isInstallDiff() ){
	die "diff not installed.";
}

my $fileList = undef;
my $srev = '';
my $erev = '';
my $address = $argv->[0];
my $outputFile = $argv->[1];

# オプション指定でリビジョンが存在か確認
if( exists $gOptions->{'r_start'} ){
	# オプション指定がある
	($srev, $erev, $fileList) = getRevisionNumber($address, "-r $gOptions->{'r_end'}:$gOptions->{'r_start'} --verbose" );
}
else{
	# ブランチの最初と最後のリビジョンを取得する
	($srev, $erev, $fileList) = getRevisionNumber($address, "--stop-on-copy --verbose" );
}
# 対象ファイル生成
my $ptn = 'c|h|cpp|hpp|cxx|hxx';
if( defined $gOptions->{'t'} ){
	$ptn = $gOptions->{'t'};
}

# 除外パス生成
my $withoutPath = undef;
if( defined $gOptions->{'wo'} ){
	$withoutPath = getWithoutPath($gOptions->{'wo'});
}

# 対象ファイルリスト生成
my $targetFileList=undef;
$targetFileList->{$srev} = getFileList( $address, $srev, $ptn, $withoutPath); # start
$targetFileList->{$erev} = getFileList( $address, $erev, $ptn, $withoutPath); # end

my $analyzeReport = analyzeFileList( $address, $targetFileList, $srev, $erev);
exportFile($address, $outputFile, $analyzeReport);
print "complate.\n";
exit;

sub dbg_print
{
	my ($string) = @_;
	if( defined $gOptions->{'dbg'} ){
		print encode('cp932', $string);
	}
}

sub analyzeFileList
{
	my ( $address, $targetFileList, $srev, $erev) = @_;

	mkdir "tmp";
	print "exporting... [$srev]\n";
	svnCmd("export","-r $srev", $address, "tmp\/$srev");
	print "exporting... [$erev]\n";
	svnCmd("export","-r $erev", $address, "tmp\/$erev");

	print "analyzing... [$srev][$erev]\n";
	my %outFileList = ();
	$outFileList{'srev'} = $srev;
	$outFileList{'erev'} = $erev;
	foreach my $file (@{$targetFileList->{$erev}}){
		my $param = \%{$outFileList{'param'}{$file}};
		my $sfile_sjis = encode('cp932', "tmp\/$srev\/$file");
		# 過去にファイルが存在しているか確認
		if( -f $sfile_sjis ){
			my ($sline,$slinew) = createFileWithoutCommnet("tmp\/$srev\/$file");
			my ($eline,$elinew) = createFileWithoutCommnet("tmp\/$erev\/$file");
			my ($add,$del) = getModifiedLine("tmp\/$srev\/$file", "tmp\/$erev\/$file");
			my ($addw,$delw) = getModifiedLine("tmp\/$srev\/$file\.woc", "tmp\/$erev\/$file\.woc");
			$param->{'sline'} = $sline;
			$param->{'eline'} = $eline;
			$param->{'slinew'} = $slinew;
			$param->{'elinew'} = $elinew;
			
			$param->{'new'} = 0;
			$param->{'dvs'} = $sline - $del;
			$param->{'add'} = $add;
			$param->{'del'} = $del;
			
			$param->{'neww'} = 0;
			$param->{'dvsw'} = $slinew - $delw;
			$param->{'addw'} = $addw;
			$param->{'delw'} = $delw;
		}
		else{
			# 追加ファイル
			my ($eline,$elinew) = createFileWithoutCommnet("tmp\/$erev\/$file");
			$param->{'sline'} = 0;
			$param->{'eline'} = $eline;
			$param->{'slinew'} = 0;
			$param->{'elinew'} = $elinew;
			
			$param->{'new'} = $eline;
			$param->{'dvs'} = 0;
			$param->{'add'} = 0;
			$param->{'del'} = 0;
			
			$param->{'neww'} = $elinew;
			$param->{'dvsw'} = 0;
			$param->{'addw'} = 0;
			$param->{'delw'} = 0;
		}
	}
	# 削除済みファイルの検索
	foreach my $file (@{$targetFileList->{$srev}}){
		my $param = \%{$outFileList{'param'}{$file}};
		my $efile_sjis = encode('cp932', "tmp\/$erev\/$file");
		if( -f $efile_sjis ){
			next;
		}
		# 削除ファイル
		my ($sline,$slinew) = createFileWithoutCommnet("tmp\/$srev\/$file");
		$param->{'sline'} = $sline;
		$param->{'eline'} = 0;
		$param->{'slinew'} = $slinew;
		$param->{'elinew'} = 0;
		
		$param->{'new'} = 0;
		$param->{'dvs'} = 0;
		$param->{'add'} = 0;
		$param->{'del'} = $sline;
		
		$param->{'neww'} = 0;
		$param->{'dvsw'} = 0;
		$param->{'addw'} = 0;
		$param->{'delw'} = $slinew;
	}
	if( !exists $gOptions->{'tmp_not_delete'} ){
		print "tmp delete\n";
		File::Path::rmtree("tmp") or die "[tmp]$!";
	}
	return \%outFileList;
}

sub createFileWithoutCommnet
{
	my ($file) = @_;
	
	my $file_sjis = encode('cp932', "$file");
	open (IN, "<$file_sjis") or die "[$file_sjis]$!";
	my @total = <IN> ;
	close IN;
	
	my $totalString = decode('cp932', join '', @total);
	# ファイルタイプ別に処理する必要がある
	$totalString =~ s#/\*[^*]*\*+([^/*][^*]*\*+)*/|//[^\n]*|("(\\.|[^"\\])*"|'(\\.|[^'\\])*'|.[^/"'\\]*)#defined $2 ? $2 : ""#gse;
	my @source = split /\n/, $totalString;
	my @sourceWithoutCommnet = ();
	foreach my $line (@source){
		if( $line =~ /^\s*$/ ){ # 空行は削除
			next;
		}
		push @sourceWithoutCommnet,$line."\n";
	}
	my $sourceWithoutCommnetString = join '', @sourceWithoutCommnet;
	my $outfile_sjis = encode('cp932', "$file\.woc");
	open (OUT, ">$outfile_sjis") or die "[$outfile_sjis]$!";
	print OUT encode('cp932', $sourceWithoutCommnetString);
	close OUT;
	my $line = @source;
	my $lineWithoutCommnet = @sourceWithoutCommnet;
	return ($line,$lineWithoutCommnet);
}

sub exportFile
{
	my ($address, $file,$analyzeReport) = @_;
	print "export file.\n";
	
	my $srev = $analyzeReport->{'srev'};
	my $erev = $analyzeReport->{'erev'};

	my $file_sjis = encode('cp932', "$file");
	open (OUT, ">$file_sjis") or die "[$file_sjis]$!";
	print OUT encode('cp932', "$address\[rev\.$srev \- $erev\], 差分,ソース行数,,,,,,コメント除去行数,,,,,\n");
	print OUT encode('cp932', "ファイル名,種類,元,変更後,新規,流用,修正,削除,元,変更後,新規,流用,修正,削除\n");
	foreach my $file ( sort keys %{$analyzeReport->{'param'}} ){
		my $param = \%{$analyzeReport->{'param'}{$file}};
		my $type = $file;
		$type =~ s/^.+?\.(.+?)$/$1/;
		my $line = encode('cp932', "$file,$type,$param->{'sline'},$param->{'eline'},$param->{'new'},$param->{'dvs'},$param->{'add'},$param->{'del'},$param->{'slinew'},$param->{'elinew'},$param->{'neww'},$param->{'dvsw'},$param->{'addw'},$param->{'delw'}\n");
		print OUT $line;
	}
	close OUT;
}


sub getModifiedLine
{
	my ($sfile, $efile) = @_;
	my $cmd = "$gOptions->{'script_path'}\/diff.exe $sfile $efile";
	$cmd =~ tr/\//\\/;
	my $res = execCmd($cmd);
	dbg_print("diff [$sfile][$efile]\n");
	dbg_print(join '' , @{$res});
	my $add = 0; my $del = 0;
	foreach my $string (@{$res}){
		if( $string =~ /^< / ){
			$del++;
		}
		elsif( $string =~ /^> / ){
			$add++;
		}
	}
	return ($add, $del);
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
	print "create file list.[$rev]\n";
	
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
	dbg_print("cmd : $cmd\n");
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
	dbg_print("cmd : $cmd\n");
	my $res = `$cmd 2>&1`;
	my @array = split /\n/,$res;
	dbg_print(join '', @array);
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
	if( exists $gOptions->{'u'} ){
		$res = "--username $gOptions->{'u'}";
	}
	if( exists $gOptions->{'p'} ){
		$res = $res." --password  $gOptions->{'p'}";
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

sub isInstallDiff
{
	my $cmd = "$gOptions->{'script_path'}\/diff.exe";
	$cmd =~ tr/\//\\/;
	my $res = execCmd($cmd);
	my $string = join '', @{$res};
	if( $string =~ /diff.+?--help/g ){
		return 1; # installed.
	}
	return 0; # not install.
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
	my ($address, $option) = @_;
	
	print "checking repository... [$address]\n";
	# --stop-on-copy を指定するとブランチができたポイントまでとなる
	# --verbose を指定すると追加／削除／変更がファイル単位で分かる
	my $resArray = svnCmd("log", $option, "\"$address\"", "");
	
	my @revs = ();
	my %fileList = ();
	while( my $line = pop(@{$resArray}) ){ # 過去からさかのぼる
		dbg_print($line);
		if( $line =~ /^r([0-9]+) |.+ lines$/ ){
			push @revs, $1;
		}
		
		if( 1 <= @revs ){
			if( $line =~ /^   ([MADR]{1}) (\/.+?)$/ ){
				my $a1 = $1; my $a2 = $2;
				if( $a2 =~ /\(from .+\)/ ){
					next; # 意味不明フォルダなんでfilelistの対象としない
				}
				# A 項目が追加されました。
				# D 項目が削除されました。
				# M 項目の属性やテキスト内容が変更されました。
				# R 項目が同じ場所の違うもので置き換えられました。
				if( exists $fileList{$a2} ){
					if( ($fileList{$a2} ne 'A') && ($a1 eq 'D') ){ # 最初が追加の場合は、上書きは削除しか認めない
						delete($fileList{$a2}); # 最初から無かったことにする
					}
					elsif( ($fileList{$a2} ne 'D') && ($a1 eq 'A') ){ # 最初が削除の場合は、上書きは追加しか認めない
						$fileList{$a2} = 'M'; # 変更扱いとしておく
					}
				else{
					$fileList{$a2} = $a1;
				}
				}
				else{
					$fileList{$a2} = $a1;
				}
			}
		}
	}
	if( 1 >= @revs ){
		die "[$address] is no history.\n";
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
			if( $param !~ /^(\d+):(\d+)$/ ) {
				die "illigal parameter with options ($key = $param)";
			}
			$options{'r_start'} = $1;
			$options{'r_end'} = $2;
			$i++;
		}
		elsif( $key =~ /^-(u|p|t|xls|wo)$/ ){ # key = value;
			$options{$1} = decode('cp932', $argv->[$i+1]);
			$i++;
		}
		elsif( $key =~ /^-(tmp_not_delete|dbg)$/ ){
			$options{$1} = 1;
		}
		elsif( $key =~ /^-/ ){
			die "illigal parameter with options ($key)";
		}
		else{
			push @newAragv, $key;
		}
	}
	return (\@newAragv, \%options);
}

