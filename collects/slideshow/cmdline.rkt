
(module cmdline mzscheme
  (require mzlib/class
           mzlib/unit
	   mzlib/file
	   mzlib/etc
	   mzlib/contract
	   mred
	   mzlib/cmdline
	   texpict/mrpict
	   texpict/utils
	   mzlib/math
	   "sig.ss"
	   (prefix start: "start-param.ss"))

  (provide cmdline@)

  (define-unit cmdline@
    (import)
    (export (prefix final: cmdline^))
    
    (define-values (screen-w screen-h) (values 1024 768))
    (define base-font-size 32)

    (define-values (actual-screen-w actual-screen-h) (get-display-size #t))
    (define-values (use-screen-w use-screen-h) (values actual-screen-w actual-screen-h))

    (define condense? #f)
    (define printing-mode #f)
    (define commentary? #f)
    (define commentary-on-slide? #f)
    (define show-gauge? #f)
    (define keep-titlebar? #f)
    (define show-page-numbers? #t)
    (define quad-view? #f)
    (define pixel-scale (if quad-view? 1/2 1))
    (define print-slide-seconds? #f)
    (define use-offscreen? #t)
    (define use-transitions? use-offscreen?)
    (define talk-duration-minutes #f)
    (define trust-me? #f)
    (define no-squash? #t)
    (define two-frames? #f)
    (define use-prefetch? #t)
    (define use-prefetch-in-preview? #f)
    (define print-target #f)
    (define smoothing? #t)
    
    (define init-page 0)
    
    (define (die name . args)
      (fprintf (current-error-port) "~a: ~a\n" name (apply format args))
      (exit -1))
    
    (define file-to-load
      (command-line
       "slideshow"
       (current-command-line-arguments)
       [once-each
        (("-d" "--preview") "show next-slide preview (useful on a non-mirroring display)" 
         (set! two-frames? #t))
        (("-p" "--print") "print"
         (set! printing-mode 'print))
        (("-P" "--ps") "print to PostScript"
         (set! printing-mode 'ps))
        (("-D" "--pdf") "print to PDF"
         (set! printing-mode 'pdf))
        (("-o") file "set output file for PostScript or PDF printing"
         (set! print-target file))
        (("-c" "--condense") "condense"
         (set! condense? #t))
        (("-t" "--start") page "set the starting page"
         (let ([n (string->number page)])
           (unless (and n 
                        (integer? n)
                        (exact? n)
                        (positive? n))
             (die 'slideshow "argument to -t is not a positive exact integer: ~a" page))
           (set! init-page (sub1 n))))
        (("-q" "--quad") "show four slides at a time"
         (set! quad-view? #t)
         (set! pixel-scale 1/2))
        (("-n" "--no-stretch") "don't stretch the slide window to fit the screen"
         (when (> actual-screen-w screen-w)
           (set! actual-screen-w screen-w)
           (set! actual-screen-h screen-h)))
        (("-s" "--size") w h "use a <w> by <h> window"
         (let ([nw (string->number w)]
               [nh (string->number h)])
           (unless (and nw (< 0 nw 10000))
             (die 'slideshow "bad width: ~e" w))
           (unless (and nh (< 0 nh 10000))
             (die 'slideshow "bad height: ~e" h))
           (set! actual-screen-w nw)
           (set! actual-screen-h nh)))
        (("-a" "--squash") "scale to full window, even if not 4:3 aspect"
         (set! no-squash? #f))
        (("-m" "--no-smoothing") 
         "disable anti-aliased drawing (usually faster)"
         (set! smoothing? #f))
        ;; Disable --minutes, because it's not used
        #;
        (("-m" "--minutes") min "set talk duration in minutes"
        (let ([n (string->number min)])
        (unless (and n 
        (integer? n)
        (exact? n)
        (positive? n))
        (die 'slideshow "argument to -m is not a positive exact integer: ~a" min))
        (set! talk-duration-minutes n)))
        (("-i" "--immediate") "no transitions"
         (set! use-transitions? #f))
        (("--trust") "allow slide program to write files and make network connections"
         (set! trust-me? #t))
        (("--no-prefetch") "disable next-slide prefetch"
         (set! use-prefetch? #f))
        (("--preview-prefetch") "use prefetch for next-slide preview"
         (set! use-prefetch-in-preview? #t))
        (("--keep-titlebar") "give the slide window a title bar and resize border"
         (set! keep-titlebar? #t))
        (("--comment") "display commentary in window"
         (set! commentary? #t))
        (("--comment-on-slide") "display commentary on slide"
         (set! commentary? #t)
         (set! commentary-on-slide? #t))
        (("--time") "time seconds per slide" (set! print-slide-seconds? #t))]
       [args slide-module-file
             (cond
              [(null? slide-module-file) #f]
              [(null? (cdr slide-module-file)) 
               (let ([candidate (car slide-module-file)])
                 (unless (file-exists? candidate)
                   (die 'slideshow "expected a filename on the commandline, given: ~a"
                        candidate))
                 candidate)]
              [else (die 'slideshow
                         "expects at most one module file, given ~a: ~s"
                         (length slide-module-file)
                         slide-module-file)])]))

    (define printing? (and printing-mode #t))

    (when (or printing-mode condense?)
      (set! use-transitions? #f))

    (when printing-mode
      (set! use-offscreen? #f)
      (set! use-prefetch? #f)
      (set! keep-titlebar? #t))

    (dc-for-text-size
     (if printing-mode
         (let ([p (let ([pss (make-object ps-setup%)])
                    (send pss set-mode 'file)
                    (send pss set-file
                          (if print-target
                              print-target
                              (let ([suffix
                                     (if (eq? printing-mode 'pdf)
                                         "pdf"
                                         "ps")])
                                (if file-to-load
                                    (path-replace-suffix (file-name-from-path file-to-load)
                                                         (format
                                                          (if quad-view?
                                                              "-4u.~a"
                                                              ".~a")
                                                          suffix))
                                    (format "untitled.~a" suffix)))))
                    (send pss set-orientation 'landscape)
                    (parameterize ([current-ps-setup pss])
                      (case printing-mode
                        [(print)
                         ;; Make printer-dc%
                         (when (can-get-page-setup-from-user?)
                           (let ([v (get-page-setup-from-user)])
                             (if v
                                 (send pss copy-from v)
                                 (exit))))
                         (make-object printer-dc% #f)]
                        [(ps)
                         (make-object post-script-dc% (not print-target) #f #t #f)]
                        [(pdf)
                         (make-object pdf-dc% (not print-target) #f #t #f)])))])
           ;; Init page, set "screen" size, etc.:
           (unless (send p ok?) (exit))
           (send p start-doc "Slides")
           (send p start-page)
           (set!-values (actual-screen-w actual-screen-h) (send p get-size))
           p)
         
         ;; Bitmaps give same size as the screen:
         (make-object bitmap-dc% (make-object bitmap% 1 1))))

    (start:trust-me? trust-me?)
    (start:file-to-load file-to-load)

    (set!-values (use-screen-w use-screen-h)
                 (if no-squash?
                     (if (< (/ actual-screen-w screen-w)
                            (/ actual-screen-h screen-h))
                         (values actual-screen-w
                                 (floor (* (/ actual-screen-w screen-w) screen-h)))
                         (values (floor (* (/ actual-screen-h screen-h) screen-w))
                                 actual-screen-h))
                     (values actual-screen-w actual-screen-h)))

    ;; We need to copy all exported bindings into the final:
    ;; form. Accumulating a unit from context and then invoking
    ;; it is one way to do that...
    (define-unit-from-context final@ cmdline^)
    (define-values/invoke-unit final@ (import) (export (prefix final: cmdline^)))))
