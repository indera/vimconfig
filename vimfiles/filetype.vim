if exists("did_load_filetypes")
    finish
endif

augroup filetypedetect
    autocmd! BufRead,BufNewFile *.ino           setf arduino
    autocmd! BufRead,BufNewFile */arduino/*.cpp setf arduino
    autocmd! BufRead,BufNewFile */arduino/*.h   setf arduino
    autocmd! BufRead,BufNewFile *.todo          setf todo
    autocmd! BufRead,BufNewFile *.applescript   setf applescript
    autocmd! BufRead,BufNewFile *.scpt          setf applescript
    autocmd! BufRead,BufNewFile *.conf          setf conf
augroup END