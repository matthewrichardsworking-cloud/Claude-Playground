# Experiments

One folder per experiment, named `YYYY-MM-DD-short-name`. To start one:

    cp -r experiments/_template experiments/$(date +%F)-my-idea

Each folder has a `README.md` and, if there's anything to run, an executable
`check.sh`. CI runs every `check.sh` it finds, so a red build points at the
experiment that broke.
