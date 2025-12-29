$out_dir = 'build';
$pdf_mode = 4;

# After the build is finished, copy the PDF back to the root folder
$post_system = 'cp "$out_dir/$jobname.pdf" .';