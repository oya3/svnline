機能：
SVN で管理されたソース差分から総ライン数、コメント除去後ライン数を生成する。
また、各ファイル単位に流用行数、追加行数、削除行数も生成する。
※現状、C/C++ のみコメント除去可能。

使い方：
perl svnline.pl [options] <svn address> <output file>

本ツールは、unix command の diff が必要です。 
http://www.gnu.org/software/diffutils/diffutils.html
http://gnuwin32.sourceforge.net/packages/diffutils.htm

仕様：
指定された svn address の開始、終了（最新）リビジョンから各行数を取得する。
オプションで開始、終了リビジョンを指定することも可能。

動作確認：
windows 7(32,64)環境のみ

同梱内容：
svnline.pl
