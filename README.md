# sample-reads

This repository contains a snakemake workflow file (**`sample_reads.smk`**) that, given a set of folders with specified sub-directories and file names for BAM files, does the following:

1. Gets a list of all combinations of CB and RG tags present in a BAM file
2. Randomly splits the CBxRG combos into N groups
3. Extracts reads for each random sample into separate BAM files

## Installation

First, clone or download this repository. Then, there are three main dependencies:

1. Python 3.9+
2. Snakemake 7+
3. samtools 1.16+

These can all be installed with [conda](https://docs.conda.io/en/latest/) or [mamba](https://mamba.readthedocs.io/en/latest/index.html). An environment file is provided as `environment.yml`. To install it (you will need conda installed already), do the following:

```bash
conda env create --file=environment.yml
```

This will create a conda environment called **sample-reads**. Next to activate the environment:

```bash
conda activate sample-reads
```

## Setting up the config file

The pipeline depends on file paths and options provided in the config file. `sample-reads-cfg.yml` is provided as an example and template and can be used, or a new config file could be created with it. The config file contains several variables that the snakemake file reads in at runtime:

| Variable | Description | 
| -------- | ----------- |
| `project_dir` | The main project directory that contains sub-directories and BAM files to sample and split |
| `subdirs` | A list of sub-directories within each directory contained in `project_dir` to look for BAM files |
| `bam_name` | The name of the BAM file to search for in each of the `subdirs` |
| `num_split` | The number of chunks to split the CB and RG combos from each BAM file |
| `random_seed` | For reproducibility, set a seed for randomly sampling each split. This is formatted like a Python dictionary, so for a different `num_split` you can add a different seed
| `out_prefix` | The prefix for all output files created by the workflow |
| `slurm_log_dir` | Each instance of each rule is submitted as a job to SLURM, so this specifies where the SLURM logs are saved |

All of these parameters are REQUIRED.

Specifically, your file tree for the project should look something like this:

```bash
project_dir
├── project_subdir[0]
│   ├── subdirs[0]
│   │   └── bam_name
│   └── subdirs[1]
│       └── bam_name
└── project_subdir[1]
    ├── subdirs[0]
    │   └── bam_name
    └── subdirs[1]
        └── bam_name
```

All directories in the `project_dir` are read automatically into the `project_subdir` list. 

Also note that each `subdir` can have other files or directories in them, they will just be ignored.

## Setting up the cluster profile

Each BAM file that is found as input (with `bam_name` inside of each of the `subdirs`) is processed in parallel as separate rules in the snakemake workflow, and each instance of the rule is submitted as a job to SLURM. SLURM jobs need some setup as well, and in the `profiles/slurm_profile/config.yaml` file a template of a job submission script is provided as well as default resource allocations. Please review this file and change as needed. Importantly:

1. Under `cluster-sync:` Anything in curly brackets (`{}`) is read passed as a variable from the snakemake file. For instance `{slurm_dir}` corresponds to `slurm_log_dir` from the config file, and `{rule}` corresponds to the current rule being run. Resources, like `{resources.cpus}` or `{resources.partition}` are also inserted into the job submission script here.
2. Default resources are provided in `default-resources:` and are used if no other resource specifications are used in the rule being run. To change rule-specific resources, update them in the rule in the snake file (`sample_reads.smk`).
3. To receive emails if your job fails (like any other job submission script), uncomment lines 12 and 13 and insert your email address.
4. Be sure to specify the default partition under `default-resources:` as a partition you have access to and that will accomodate the resource allocations for all rules (or set rule-specific partitions in the snake file).

## Running the pipeline

With the environment activated and the config files set up, you are now ready to run the pipeline! First, run a dry run:


```bash
snakemake -p -s sample_reads.smk --configfile sample-reads-cfg.yml --profile profiles/slurm_profile/ --dryrun
```

This should let snakemake check all the rules and files being run to be sure everything is setup correctly. If you see any red text, something is wrong. But if not, everything should be yellow and green and you should see a table of rules that are to be run. If this is the case, simply remove the `--dryrun` option from the command to actually execute the pipeline!

## Outputs

Each rule will output different files necessary for the next rule to be run. Here is a summary of the outputs for each rule:

| Rule | Input |  Output |
| ---- | ----- | ------- |
| *extract_tags* | A merged and sorted BAM file with CB and RG tags | A plaintext file called **`out_prefix`-`num_split`-barcodes.txt** with a list of all combinations of CB and RG tags that exist in the input BAM file. |
| *sample_tags* | **`out_prefix`-`num_split`-barcodes.txt** from the *extract_tags* rule | Two files: **`out_prefix`-`num_split`-N-sample.txt**, which contains the sampled CBxRG tags for sample N, and **`out_prefix`-`num_split`-N-filter.txt**, which contains the filter expression for the  tags for sample N to be read by the next rule. |
| *extract_reads* | **`out_prefix`-`num_split`-N-filter.txt** from the *sample_tags* rule | **`out_prefix`-`num_split`-N.bam** containing the extracted reads for sample N.
