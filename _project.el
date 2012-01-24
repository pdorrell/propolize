
(load-this-project
 `( (:ruby-executable ,*ruby-1.9-executable*)
    (:run-project-command (ruby-run-file ,(concat (project-base-directory) "propolize.rb")))
    (:build-function project-compile-with-command)
    (:compile-command "rake")
    (:ruby-args (,(concat "-I" (project-base-directory) "lib")))
    ) )
