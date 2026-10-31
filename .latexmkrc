$out_dir  = 'build';
$pdf_mode = 4;

$out2_dir = '.';

$lualatex = ($ENV{'NT_LATEX_ENGINE'} // 'lualatex') . ' %O %S';
