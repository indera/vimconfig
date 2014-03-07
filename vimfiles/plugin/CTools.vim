" Copyright 2014 Jacob Niehus
" jacob.niehus@gmail.com
" Do not distribute without permission.

if exists('CToolsLoaded')
    finish
endif

let CToolsLoaded=1

" Replace C-style comments with asterisks (excepts newlines and spaces)
func! s:StripComments()
    " Save window, cursor, etc. positions and last search
    let l:winSave=winsaveview()
    let l:search=@/

    if v:version >= 703
        keepj silent! %s/\m\(\/\*\)\(\_.\{-}\)\(\*\/\)\|\v$t^/\=submatch(1)
            \ .substitute(submatch(2),'[^ \n]','*','g')
            \ .submatch(3)/g
    else
        keepj silent! %s/\m\(\/\*\)\(\_.\{-}\)\(\*\/\)\|\v$t^/\=submatch(1)
            \ .substitute(substitute(substitute(submatch(2),' ',
            \ nr2char(1),'g'),'\p','*','g'),nr2char(1),' ','g')
            \ .submatch(3)/g
    endif

    keepj silent! %s/\m\(\/\/\)\(.*\)$\|\v$t^/\=submatch(1)
        \ .substitute(submatch(2),'[^ \n]','*','g')/g

    call histdel('/','\V$t^')

    " Restore window, cursor, etc. positions and last search
    call winrestview(l:winSave)
    let @/=l:search
endfunc

" Use StripComments functions to search in non-commented text only
func! s:FindNotInComment(direction)
    " Save some information to restore later
    let l:buf=bufnr('%')
    let l:winSave=winsaveview()
    let l:len=line('$')

    " Create scratch buffer
    enew
    setlocal buftype=nofile
    setlocal bufhidden=hide
    setlocal noswapfile
    setlocal buflisted
    let l:scratch=bufnr('%')

    " Copy buffer contents to scratch buffer
    for n in range(1,l:len)
        call setline(n, getbufline(l:buf, n))
    endfor

    " Get rid of comments in scratch buffer
    call s:StripComments()

    " Jump to next or previous match depending on search direction and n/N
    call winrestview(l:winSave)
    let v:errmsg=""
    let l:sfsave=getbufvar(l:buf,'sfsave')
    if (a:direction && l:sfsave) || (!a:direction && !l:sfsave)
        silent! normal! /
    else
        silent! normal! ?
    endif
    let l:errmsg=v:errmsg

    " Save view in scratch buffer
    let l:winSave=winsaveview()

    " Switch back to main buffer and wipe scratch buffer
    exec 'silent b '.l:buf
    exec 'bwipe '.l:scratch
    call winrestview(l:winSave)

    " Print normal search text
    redraw
    if (a:direction && l:sfsave) || (!a:direction && !l:sfsave)
        echo '/'.@/
    else
        echo '?'.@/
    endif

    " Give error message if there was one
    if l:errmsg != ""
        echohl ErrorMsg
        redraw
        echo l:errmsg
        echohl None
    endif
endfunc

func! s:UnmapCR()
    silent! cunmap <buffer> <CR>
    silent! cunmap <buffer> <Esc>
    silent! cunmap <buffer> <C-c>
endfunc

func! s:MapCR()
    cnoremap <buffer> <silent> <CR> <CR>``:call <SID>FindNotInComment(1)<CR>:call
        \<SID>MapN()<CR>:call <SID>UnmapCR()<CR>
    cnoremap <buffer> <silent> <Esc> <C-c>:call <SID>UnmapCR()<CR>
    cnoremap <buffer> <silent> <C-c> <C-c>:call <SID>UnmapCR()<CR>
endfunc

func! s:MapN()
    nnoremap <buffer> <silent> n :call <SID>FindNotInComment(1)<CR>
    nnoremap <buffer> <silent> N :call <SID>FindNotInComment(0)<CR>
endfunc

func! s:ToggleFindInComments()
    if !exists('b:findInComments')
        let b:findInComments=1
    endif
    if b:findInComments
        let b:sfsave=v:searchforward
        call s:MapN()
        nnoremap <buffer> <silent> / m`:call <SID>MapCR()<CR>:let b:sfsave=1<CR>:redraw<CR>:echo '/'<CR>/
        nnoremap <buffer> <silent> ? m`:call <SID>MapCR()<CR>:let b:sfsave=0<CR>:redraw<CR>:echo '?'<CR>?
        nnoremap <buffer> <silent> * m`:let @/='\<'.expand('<cword>').'\>'<CR>:let
            \ b:sfsave=1<CR>:call <SID>FindNotInComment(1)<CR>:set hlsearch<CR>
        nnoremap <buffer> <silent> # m`:let @/='\<'.expand('<cword>').'\>'<CR>:let
            \ b:sfsave=0<CR>:call <SID>FindNotInComment(1)<CR>:set hlsearch<CR>
        let b:findInComments=0
        redraw
        echo "Searching text not in C-style comments"
    else
        silent! unmap <buffer> n
        silent! unmap <buffer> N
        silent! unmap <buffer> /
        silent! unmap <buffer> ?
        silent! unmap <buffer> *
        silent! unmap <buffer> #
        call s:UnmapCR()

        " Handle case where previous search was backwards
        if b:sfsave==0
            nnoremap <buffer> <silent> n ?:unmap <buffer> n<CR>:unmap <buffer> N<CR>
            nnoremap <buffer> <silent> N ?NN:unmap <buffer> n<CR>:unmap <buffer> N<CR>
        endif
        let b:findInComments=1
        redraw
        echo "Searching everywhere"
    endif
endfunc

" Tabular pipeline for aligning = with first non-blank of lines up until ;
autocmd VimEnter * silent! AddTabularPipeline! align_with_equals
    \ /^[^=]*\zs=\([^;]*$\)\@=
    \\|^\s*\zs=\@<!\S[^=]*;.*$
    \\|^\s*\zs\([{}]\)\@!\(\/\/\)\@!\S[^;]*\(\*\/\)\@<!$/
    \ map(a:lines,"substitute(v:val,'^\\s*\\(.*=\\)\\@!','  ','g')")
    \ | tabular#TabularizeStrings(a:lines,
    \ '^\s*\zs  [[:alnum:]]\(.*=\)\@!.*$\
    \|^\s*\zs[^[:alnum:][:blank:]]\(.*=\)\@!.*$\
    \|^[^=]*\zs=\([^;]*$\)\@=.*$','l1')

" Handle +=, -=, etc.
autocmd VimEnter * silent! AddTabularPipeline! align_with_equals_after1char
    \ /^[^=]*\zs=\([^;]*$\)\@=
    \\|^\s*\zs=\@<!\S[^=]*;.*$
    \\|^\s*\zs\([{}]\)\@!\(\/\/\)\@!\S[^;]*\(\*\/\)\@<!$/
    \ map(a:lines,"substitute(v:val,'^\\s*\\(.*=\\)\\@!','   ','g')")
    \ | tabular#TabularizeStrings(a:lines,
    \ '^\s*\zs   [[:alnum:]]\(.*=\)\@!.*$\
    \|^\s*\zs [^[:alnum:][:blank:]]\(.*=\)\@!.*$\
    \|^[^=]*\zs[+*/%&|^-]=[^;=]*$','l1')

" Handle <<= and >>=
autocmd VimEnter * silent! AddTabularPipeline! align_with_equals_after2char
    \ /^[^=]*\zs=\([^;]*$\)\@=
    \\|^\s*\zs=\@<!\S[^=]*;.*$
    \\|^\s*\zs\([{}]\)\@!\(\/\/\)\@!\S[^;]*\(\*\/\)\@<!$/
    \ map(a:lines,"substitute(v:val,'^\\s*\\(.*=\\)\\@!','    ','g')")
    \ | tabular#TabularizeStrings(a:lines,
    \ '^\s*\zs    [[:alnum:]]\(.*=\)\@!.*$\
    \|^\s*\zs  [^[:alnum:][:blank:]]\(.*=\)\@!.*$\
    \|^[^=]*\zs\(<<\|>>\)=[^;=]*$','l1')

" Function to find and align lines of a C assignment
func! s:AlignUnterminatedAssignment()
    if !hlexists('cComment') | return 0 | endif
    if !exists(':Tabularize') | return 0 | endif

    " Pattern to find an unterminated assignment
    let l:pat='^.*[=!<>]\@<!\zs=\ze=\@![^;]*$\|^.*\zs\(<<\|>>\)=\ze[^;]*$'

    " Find start of expression
    " Can't be in string, in parens, after open paren, at EOL, in a comment,
    " or in a preprocessor macro
    let l:top=search(l:pat,'W')
    if !l:top | return 0 | endif
    while     getline(l:top) =~ "\"[^\"=;]*=[^\"]*\"[^\"=;]*$"
        \ ||  getline(l:top) =~ "'[^'=;]*=[^'=;]*'[^'=;]*$"
        \ ||  getline(l:top) =~ "([^()=;]*=[^()=;]*)[^()=;]*$"
        \ || (getline(l:top) =~ '=[^=;()]*[[:alnum:]]\+\s*([^=;()]*$'
        \  && getline(l:top+1) =~ '^\s*[[:alnum:]]')
        \ ||  getline(l:top) =~ "=$"
        \ || (synIDattr(synID(line("."), col("."), 1), "name")) =~? 'comment'
        \ ||  getline(l:top) =~ "^\s*#"
        let l:top=search(l:pat,'W')
        if !l:top | return 0 | endif
    endwhile

    " Find end of expression
    let l:bottom=search(';','W')
    if !l:bottom | return 0 | endif
    while (synIDattr(synID(line("."), col("."), 1), "name")) =~? 'comment'
        let l:bottom=search(';','W')
        if !l:bottom | return 0 | endif
    endwhile

    " Tabularize
    if getline(l:top) =~ '\(<<\|>>\)='
        exec l:top.','.l:bottom.'Tabularize align_with_equals_after2char'
    elseif getline(l:top) =~ '[+*/%&|^-]='
        exec l:top.','.l:bottom.'Tabularize align_with_equals_after1char'
    else
        exec l:top.','.l:bottom.'Tabularize align_with_equals'
    endif
    call cursor(l:bottom, 1)
    return 1
endfunc

" Function to fully format a C/C++ source file
func! s:FormatC()
    if !hlexists('cComment') | return | endif

    " Save view to restore afterwards
    let l:winSave=winsaveview()

    " Replace tabs with spaces or vice versa
    retab

    " Remove trailing whitespace
    keepj silent! %s/\s\+$\|\v$t^//g | call histdel('/','\V$t^')

    " Go through all lines and indent correctly
    call cursor(1,1)
    let line1done=0
    while line('.') < line('$')
        if line1done
            norm! j^
        else
            let line1done=1
        endif
        if getline('.') != ""
            if (getline('.') !~ '^\s*\/\*') || (getline('.') =~ '^\s*\/\*.*\*\/')
                if getline('.') !~ '^\s*#'
                    " Regular line of code or single-line comment
                    norm! ==
                endif
            else
                " First line of block comment
                let l:top=line('.')
                let l:indent=cindent(l:top)-match(getline('.'),'\S')
                call search('^.*\*\/','W')
                let l:bottom=line('.')

                " Indent all lines of block comment by same amount
                while l:indent
                    if l:indent > 0
                        exec 'keepj silent! '.l:top.','.l:bottom.'s/^.*$\|\v$t^/ &'
                        let l:indent -= 1
                    else
                        let l:space=1
                        for n in range(l:top,l:bottom)
                            if match(getline(n),'\S') == 0
                                let l:space=0
                            endif
                        endfor
                        if l:space
                            exec 'keepj silent! '.l:top.','.l:bottom.'s/^\( \)\(.*\)$\|\v$t^/\2'
                            let l:indent += 1
                        else
                            let l:indent=0
                        endif
                    endif
                endwhile
            endif
        endif
    endwhile

    " Find and indent unterminated assignments
    call cursor(1,1)
    while s:AlignUnterminatedAssignment() | endwhile

    " Clean up search history
    call histdel('/','\V$t^')

    " Restore view
    call winrestview(l:winSave)
endfunc

com! StripComments call <SID>StripComments()
com! ToggleFindInComments call <SID>ToggleFindInComments()
com! AlignUnterminatedAssignment call <SID>AlignUnterminatedAssignment()
com! FormatC call <SID>FormatC()

nnoremap ,c :ToggleFindInComments<CR>

