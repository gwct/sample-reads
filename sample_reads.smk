#############################################################################
# Pipeline for sampling reads from BAM files and splitting randomly by certain
# tags (e.g. CB and RG)
#############################################################################

import os
import re

#############################################################################

## Example commands
#############################################################################

project_dir = config["project_dir"];
subdirs = config["subdirs"];
bam_input = config["bam_name"];
num_split = config["num_split"];
output_prefix = config["out_prefix"];
slurm_dir = config["slurm_log_dir"];
random_seed = config["random_seed"][num_split];

## Read info from config file
#############################################################################

project_subdirs = os.listdir(project_dir);
split_list = list(range(1, num_split+1));

## A bit of Python to get the top-level subdirs and a list of splits
#############################################################################

localrules: all

rule all:
    input:
        expand(os.path.join(project_dir, "{project_subdir}", "{subdir}", output_prefix + "-" + str(num_split) + "-{cur_split}.bam"), project_subdir=project_subdirs, subdir=subdirs, cur_split=split_list)
        #expand(os.path.join(project_dir, "{project_subdir}", "{subdir}", "pseudobulk-" + str(num_split) + "-{cur_split}-sample.txt"), project_subdir=project_subdirs, subdir=subdirs, cur_split=split_list),
        #expand(os.path.join(project_dir, "{project_subdir}", "{subdir}", "pseudobulk-" + str(num_split) + "-{cur_split}-filter.txt"), project_subdir=project_subdirs, subdir=subdirs, cur_split=split_list)

        

        #expand(os.path.join(project_dir, "{project_subdir}", "{subdir}", "pseudobulk-" + str(num_split) + "-barcodes.txt"), project_subdir=project_subdirs, subdir=subdirs)
        
# The final rule (all), the "input" of which should be the final desired
# files from the pipeline
#############################################################################
# Below are the pipeline rules

rule extract_tags:
    input:
        os.path.join(project_dir, "{project_subdir}", "{subdir}", bam_input)
    output:
        os.path.join(project_dir, "{project_subdir}", "{subdir}", "pseudobulk-" + str(num_split) + "-barcodes.txt")
    resources:
        cpus = 1,
        time = "2:00:00"
    shell:
        """
        samtools view --threads {resources.cpus} --keep-tag CB --keep-tag RG {input} | cut -f 12,13 | sort | uniq > {output}
        """

# Rule to select all unique combinations of CB and RG tags
# NOTE: This could be generalized for any number of tags, but for now CB and RG are hardcoded as the
# tags of interest
#################

rule sample_tags:
    input:
        barcodes = os.path.join(project_dir, "{project_subdir}", "{subdir}", "pseudobulk-" + str(num_split) + "-barcodes.txt")
    output:
        sample_file = os.path.join(project_dir, "{project_subdir}", "{subdir}", "pseudobulk-" + str(num_split) + "-{cur_split}-sample.txt"),
        filter_file = os.path.join(project_dir, "{project_subdir}", "{subdir}", "pseudobulk-" + str(num_split) + "-{cur_split}-filter.txt")
    params:
        output_file_prefix = os.path.join(project_dir, "{project_subdir}", "{subdir}", "pseudobulk-" + str(num_split)),
        seed = random_seed,
        splits = num_split
    resources:
        mem = "4g",
        time = "1:00:00"
    run:
        import random
        print("# Setting random seed: " + str(params.seed));
        random.seed(params.seed)
        ## Import the random module and set the seed

        barcodes = open(input.barcodes, "r").read().split("\n")[:-1]
        barcodes = list(set([ barcode[:barcode.rfind(":")] for barcode in barcodes ]))
        barcodes.sort()
        random.shuffle(barcodes)
        ## Remove the flowcell info and remove resulting duplicates, then sort and shuffle the list of barcodes 

        subsets = [[] for i in range(params.splits) ];
        subset_ind = 0;
        for barcode in barcodes:
            subsets[subset_ind].append(barcode);
            subset_ind += 1;
            if subset_ind == params.splits:
                subset_ind = 0;
        ## Get subsets of the shuffled list of barcodes

        for i in range(len(subsets)):
            subset = subsets[i];
            # Get the current subset of barcodes

            filters = [];
            # Initialize an empty list of filters for samtools -e

            cur_sample_file = os.path.join(params.output_file_prefix + "-" + str(i+1) + "-sample.txt");
            # Define the output file listing all sampled CB and RG combinations for this subset

            with open(cur_sample_file, "w") as samplefile:
                for barcode in subset:
                    samplefile.write(barcode + "\n");
                    # Write each barcode to the current sample file

                    cb, rg = barcode.split("\t");
                    cb = cb[5:];
                    # Remove the tag label and Type portion (e.g. Z:) of the CB tag
                    # Assumes CB tag always begins CB:Z:

                    rg = rg[5:];
                    # Remove the tag label and Type portion (e.g. Z:) of the RG tag
                    # Assumes RG tag always beings RG:Z:

                    cur_filter_str = "([CB]==\"" + cb + "\" && [RG]=~\"" + rg + "*\")";
                    filters.append(cur_filter_str);
                    # Construct a filter string for this combination of tags in samtools - syntax
                    # For read group, we use a regular expression (with =~) at the end of the string (*) to 
                    # match any flowcell with that name since these were removed above
                ## End barcode loop for current subset
            ## Close sample file

            cur_filter_file = os.path.join(params.output_file_prefix + "-" + str(i+1) + "-filter.txt");
            # Define the output file listing with the filter strings for this subset

            with open(cur_filter_file, "w") as filterfile:
                filters = "'" + " || ".join(filters) + "'";
                filterfile.write(filters);
            ## Join and write the filter strings
        ## End subset loop

# Rule to parse and randomly sample CBxRG tag combinations
# This rule uses inline Python instead of running a command in the shell
# The Python code could easily be moved to its own script and called via shell or script if that
# is easier to read
#################

rule extract_reads:
    input:
        bam = os.path.join(project_dir, "{project_subdir}", "{subdir}", bam_input),
        filter_file = os.path.join(project_dir, "{project_subdir}", "{subdir}", "pseudobulk-" + str(num_split) + "-{cur_split}-filter.txt")
    output:
        os.path.join(project_dir, "{project_subdir}", "{subdir}", output_prefix + "-" + str(num_split) + "-{cur_split}.bam")
    resources:
        cpus = 1
    shell:
        """
        filter=$( cat {input.filter_file} )
        cmd="samtools view --threads {resources.cpus} -e $filter {input.bam} > {output}"
        eval $cmd
        """

# Rule to extract reads based on the sampling in sample_tags by using samtools view -e filters
#################