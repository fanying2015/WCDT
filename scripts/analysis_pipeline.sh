BASESPACE=/home/zoltan/BaseSpace/Projects
DIR_BASE=/notebook/human_sequence_prostate_WCDT/WCDT
DIR_SCRIPTS=${DIR_BASE}/scripts
BUILD_ID=2018_04_15
DIR_OUT=/mnt/rad51/datasets_1/human_sequence_prostate_WCDT/build_${BUILD_ID}

DIR_BASESPACE_BASE_DNA=${BASESPACE}/WGS-TNv2/AppResults
DIR_BASESPACE_BASE_RNA=${BASESPACE}/RNAseq-alignment/AppResults
HG38_FA=/mnt/rad51/raw/human_sequence_reference/UCSC/GRCh38Decoy/Sequence/WholeGenomeFasta/genome.fa
CHROM_NAMES=${DIR_BASE}/metadata/chromosome_names.txt
REFFLAT=${DIR_BASE}/metadata/GRCh38Decoy_refseq_genelocs_from_refFlat.bed
GENE_LENGTH=${BASE_NOTEBOOK}/metadata/GCh38Decoy_counts_genelength.txt

RAM=8
SNPSIFT=/opt/snpEff/SnpSift.jar
SA=20180123_sample_attributes.txt
BEDTOOLS_BIN=/opt/bedtools2/bin
BGZIP=/opt/htslib-1.3.1/bgzip
BCFTOOLS=/opt/bcftools-1.2/bcftools
TABIX=/opt/htslib-1.3.1/tabix


##################################
# Extract sequencing statistics
##################################
#
#----------------------------------------
# Read summary.csv sequencing summary data generated by illumina pipeline
# write summaries to DIR_OUT: matrix_alignment_summary_normal.txt,
# matrix_alignment_summary_tumor.txt
python ${DIR_SCRIPTS}/collect_sequence_statistics.py \
  -s ${DIR_BASE}/metadata/${SA} 
  -o ${DIR_OUT}

##################################
# COPY DATA FROM BASESPACE
##################################
#
#----------------------------------------
#
# extract_illumina_files.py
# Pull files out of basespace
python ${DIR_SCRIPTS}/extract_illumina_files.py \
  -i ${DIR_BASE}/metadata/${SA} \
  -d ${DIR_BASESPACE_BASE_DNA} \
  -r ${DIR_BASESPACE_BASE_RNA} \
  -f \
  -o ${DIR_OUT}

##################################
# GERMLINE 
##################################
#
#----------------------------------------
#
# extract_pathogenic_germline.sh
# IN:
#      all germline VCF files generated by Strelka
# OUT:  
#      ${SAMPLE_ID}_illumina_germline_filtered.vcf   input filtered only for results pertaining to that sample
#      ${SAMPLE_ID}_illumina_germline_pathogenic.vcf suspected pathogenic variants
bash ${DIR_SCRIPTS}/extract_pathogenic_germline.sh \
  -i=${DIR_BASE}/metadata/${SA} \
  -t=${DIR_BASE}/metadata/20180123_sample_attributes_ID_WGS.txt \
  -d=${DIR_OUT} \
  -o=${DIR_OUT} \
  -s=_illumina_germline \
  -p="java -Xmx${RAM}G -jar ${SNPSIFT}" \
  -c=${CHROM_NAMES}

#
#----------------------------------------
#
# collect_pathogenic_germline.py
#      in list, cosmic and variant_type from snpSift; ref/alt from Strelka
#
# IN:
#      all germline pathogenic candidate vcfs
# OUT: 
#      list_germline_summary.txt    sample_id,symbol,refseq,variant_type,chrom,pos,ref,alt,cosmic
#      matrix_germline_summary.txt  value of matrix is the germline change e.g. chr7:87431528_C>T
python ${DIR_SCRIPTS}/collect_pathogenic_germline.py \
  -d ${DIR_OUT} \
  -s _illumina_germline_pathogenic.vcf \
  -o ${DIR_OUT}/${BUILD_ID}_matrix_germline_summary.txt \
  -l ${DIR_OUT}/${BUILD_ID}_list_germline_summary.txt 
  
##################################
# COPY NUMBER
##################################
# run after cluster call to calculate_copycat.R is performed on all samples.
# Generates three matrix files (feature by sample): 
# _CNA_symbol_copycat.txt
# _CN_integer_symbol_copycat.txt
# _AR_enhancer_CN.txt (specific to AR enhancer region)
python ${DIR_SCRIPTS}/collect_CNA_copycat.py \
 -d ${DIR_OUT} \
 -o ${DIR_OUT} \
 -s _copycat.bed \
 -u ${DIR_OUT}/${BUILD_ID}_matrix \
 -b ${BEDTOOLS_BIN} \
 -g ${DIR_BASE}/metadata/GRCh38Decoy_refseq_genelocs_from_refFlat.bed


#
#----------------------------------------
#
# extract_CNA_SV.py
# IN: 
#      All manta/Canvas intermingled VCFs 
# OUT: 
#      ${SAMPLE_ID}_circos.txt       Chromosome,chromStart,chromEnd,Chromosome.1,chromStart.1,chromEnd.1
#      ${SAMPLE_ID}_canvas.bed       BED formatted file of canvas calls including status (GAIN/DEL/etc) and copy number
#      ${SAMPLE_ID}_CNA_summary.txt  ploidy, coverage, n_bnd, n_del, n_inv, n_ins, bases_CNA_ref, bases_cna_notref, percent_CNA_ref
#      ${SAMPLE_ID}_CNA_summary.txt  transcript-level summary of CNA
#      ${SAMPLE_ID}_gene_summary.bed Bed intersecting canvas calls and gene locations
#      matrix_CNA_symbol.txt         rows are symbols, cols are samples, value is CNA call from Canvas
#      matrix_CNA_refseq.txt         rows are transcripts, cols are samples, value is CNA call from Canvas
#      matrix_CN_integer_symbol.txt  rows are symbols, cols are samples, value is CN integer call from Canvas
#      matrix_CN_integer_refseq.txt  rows are transcripts, cols are samples, value is CN integer call from Canvas
python ${DIR_SCRIPTS}/extract_CNA_SV.py \
 -d ${DIR_OUT} \
 -o ${DIR_OUT} \
 -s _manta.vcf \
 -u ${DIR_OUT}/${BUILD_ID}_matrix \
 -b ${BEDTOOLS_BIN} \
 -g ${DIR_BASE}/metadata/GRCh38Decoy_refseq_genelocs_from_refFlat.bed

#
#----------------------------------------
#
# collect_binned_CNA.py
# 
#      create windowed bed file (3Mb window) to intersect with segments
#      intersect each _copycat.bed file with the segment file
# IN:
#      all files with suffix _copycat.bed
# OUT:
#      matrix_binned_weighted_CN.txt

python ${DIR_SCRIPTS}/collect_binned_CNA.py \
  -d ${DIR_OUT} \
  -s _copycat.bed \
  -o ${DIR_OUT}/${BUILD_ID} \
  -c ${DIR_BASE}/metadata/HG38_chromosome_lengths.txt \
  -b ${BEDTOOLS_BIN} \
  -w 3000000


##################################
# SOMATIC MUTATION
##################################
#
#----------------------------------------
#
# extract_somatic_SNV.sh
# IN: 
#      All vcf files generated by Strelka
# OUT: 
#      ${SAMPLE_ID}_somatic_pass_SNP.vcf,            high-quality _SNPs
#      ${SAMPLE_ID}_somatic_pass_inactivating.vcf    nonsense mutations in  
#      ${SAMPLE_ID}_somatic_pass_missense.vcf        missense mutations 
#      ${SAMPLE_ID}_pass_SNP_CPRA.txt                one line describing each high-quality SNV for deconstructSigs
#      ${SAMPLE_ID}_strelka_mutation_percentages.txt result of deconstructSigs 

# TODO
# Strelka calls
bash ${DIR_SCRIPTS}/extract_somatic_SNV.sh \
  -i=${DIR_BASE}/metadata/${SA} \
  -t=${DIR_BASE}/metadata/ID_WGS.txt \
  -d=${DIR_OUT} \
  -o=${DIR_OUT} \
  -s=_somatic \
  -v=1 \
  -p="java -Xmx${RAM}G -jar ${SNPSIFT}" \
  -c=${DIR_BASE}/metadata/chromosome_names.txt \
  -k=${DIR_SCRIPTS}/quantify_mutation_signatures.R

# Mutect calls
bash ${DIR_SCRIPTS}/extract_somatic_SNV.sh \
  -i=${DIR_BASE}/metadata/${SA} \
  -t=${DIR_BASE}/metadata/ID_WGS.txt \
  -d=${DIR_VCF} \
  -o=${DIR_OUT} \
  -s=_mutect_snpeff_filtered_clinvar \
  -p="java -Xmx${RAM}G -jar ${SNPSIFT}" \
  -c=${DIR_BASE}/metadata/chromosome_names.txt \
  -k=${DIR_SCRIPTS}/quantify_mutation_signatures.R


#
#----------------------------------------
#
# collect_mutation_signatures.py
# 
#      Create aggregate matrix of mutation signature percentages
# IN:
#      all files with suffix _strelka_mutation_percentages.txt
# OUT:
#      matrix_mutation_signature_summary.txt
python ${DIR_SCRIPTS}/collect_mutation_signatures.py \
  -d ${DIR_OUT} \
  -s _strelka_mutation_percentages.txt \
  -o ${DIR_OUT}/${BUILD_ID}_matrix_mutation_signature_summary.txt

#
#----------------------------------------
#
# collect_somatic_SNV_for_mutsig_discovery.sh
# 
#      strip somatic vcfs to tumor-only SNPs that pass and have sane chromosomes
# IN:
#      all files with ${SAMPLE_ID}_somatic.vcf
# OUT:
#      VCFs with name ${SAMPLE_ID}_somatic_PASS_clean.vcf.gz.tbi
bash ${DIR_SCRIPTS}/collect_somatic_SNV_for_mutsig_discovery.sh \
  -d=${DIR_OUT} \
  -o=${DIR_OUT}/SomaticSignatures \
  -s=${DIR_BASE}/metadata/${SA} \
  -b=${BGZIP} \
  -c=${BCFTOOLS} \
  -t=${TABIX}
    

#
#----------------------------------------
#
# Make exhaustive list of all somatic mutations with PASS, regardless of interpretation 
# of function (e.g. include non-coding genome, etc)
# IN: 
#      All VCF files generated by Strelka
# OUT: 
#      ${BUILD_ID}_list_somatic_PASS_mutations.txt: list of all somatic variants
#      matrix_mutation_count_summary.txt
python ${DIR_SCRIPTS}/collect_somatic_mutations.py \
  -d ${DIR_OUT} \
  -s _somatic.vcf \
  -l ${DIR_OUT}/${BUILD_ID}_list_somatic_PASS_mutations.txt \
  -c ${CHROM_NAMES} \
  -o ${DIR_OUT}/${BUILD_ID}_matrix_mutation_count_summary.txt

#
#----------------------------------------
#
# collect_somatic_SNV.py
# 
#      Create aggregate matrix and list of somatic and inactivating mutations
# IN:
#      all files with suffix _pass_inactivating.vcf
#      all files with suffix _pass_missense.vcf
# OUT:
#      matrix_somatic_inactvating.txt
#      matrix_somatic_missense.txt
#      list_somatic.txt
python ${DIR_SCRIPTS}/collect_somatic_SNV.py \
  -d ${DIR_OUT} \
  -t strelka \
  -o ${DIR_OUT}/${BUILD_ID} \
  -s _pass_inactivating.vcf \
  -m _pass_missense.vcf 
  
python ${DIR_SCRIPTS}/collect_somatic_SNV.py \
  -d ${DIR_OUT} \
  -t mutect \
  -o ${DIR_OUT}/${BUILD_ID}_mutect \
  -s _mutect_snpeff_filtered_clinvar_pass_inactivating.vcf \
  -m _mutect_snpeff_filtered_clinvar_pass_missense.vcf 
  


#
#----------------------------------------
#
# quantify_denovo_mutation_signatures.R
# 
#      Identify de novo signatures of mutation
# IN:
#      vcf mutation files with ${SAMPLE_ID}_somatic_PASS_clean_SNP.vcf
#      ${SAMPLE_ID}_pass_SNP_CPRA.txt files for subsequent call to deconstructSigs
# OUT:
#      mutation matrix
Rscript ${DIR_SCRIPTS}/quantify_denovo_mutation_signatures.R \
 -a ${DIR_BASE}/metadata/${SA} \
 -s _somatic_PASS_clean_SNP.vcf \
 -c _pass_SNP_CPRA.txt \
 -d ${DIR_OUT}/SomaticSignatures \
 -o ${DIR_OUT}


##################################
# STRUCTURAL VARIATION
##################################
#
#----------------------------------------
#
# collect_SV_details.py
#      MH is detected here by using pos_start and pos_end reported by Manta
#
# IN: 
#      All manta/Canvas intermingled VCFs 
# OUT: 
#      list_manta_SV.txt,     each deletion or tandem duplication found and whether deletions have microhomology
#      list_manta_fusions.txt gene fusions detected by MantaFusion
#      matrix_SV_summary.txt  summary of all SV and deletions bearing microhomology
python ${DIR_SCRIPTS}/collect_SV_details.py \
  -d ${DIR_OUT} \
  -s _manta.vcf \
  -x ${DIR_OUT}/${BUILD_ID}_matrix_SV_summary.txt \
  -o ${DIR_OUT}/${BUILD_ID}_list_manta_SV.txt \
  -f ${DIR_OUT}/${BUILD_ID}_list_manta_fusions.txt \
  -r ${DIR_OUT}/${BUILD_ID}_list_manta_chainfinder.txt \
  -g ${HG38_FA} \
  -m 5 -l 20 -n 0 -t 10 \
  -c ${CHROM_NAMES}



##################################
# RNA 
##################################

#
#----------------------------------------
#
# collect_RNA_counts.py
# 
#      Aggregate insert size and other RNA metrics
# IN:
#      all files with suffix _RNA_metrics_tumor.json
# OUT:
#      matrix_rna_metrics.txt
python ${DIR_SCRIPTS}/collect_RNA_counts.py \
  -d ${DIR_OUT} \
  -s _RNA_counts_tumor.txt \
  -o ${DIR_OUT}/${BUILD_ID}_matrix_rna_counts.txt
  
#
#----------------------------------------
#
# collect_RNA_metrics.py
# 
#      Aggregate insert size and other RNA metrics
# IN:
#      all files with suffix _RNA_metrics_tumor.json
# OUT:
#      matrix_rna_metrics.txt
python ${DIR_SCRIPTS}/collect_RNA_metrics.py \
  -d ${DIR_OUT} \
  -s _RNA_metrics_tumor.json \
  -o ${DIR_OUT}/${BUILD_ID}_matrix_rna_metrics.txt

#
#----------------------------------------
#
# calculate_RNA_tpm.R
# IN:
#      refflat file describing gene locations
#      metrics file generated by collect_RNA_metrics.py
#      counts file generated by collect_RNA_counts.py
# OUT:
#      matrix_rna_tpm.txt
Rscript ${DIR_SCRIPTS}/calculate_RNA_tpm.R \
 ${GENE_LENGTH} \
 ${DIR_OUT}/${BUILD_ID}_matrix_rna_metrics.txt \
 ${DIR_OUT}/${BUILD_ID}_matrix_rna_counts.txt \
 ${DIR_OUT}/${BUILD_ID}_matrix_rna_tpm.txt

#
#----------------------------------------
#
# synthesize_sample_matrix_results.py
# 
#      aggregate individual sample summary matrixes into a single master file
# IN:
#      ${CNA_SUMMARY},${MUT_COUNT},${MUT_SIG},${GERMLINE},${MICRO}
# OUT:
#      matrix_sample_summary.txt
MICRO=${DIR_OUT}/${BUILD_ID}_matrix_SV_summary.txt
MUT_COUNT=${DIR_OUT}/${BUILD_ID}_matrix_mutation_count_summary.txt
MUT_SIG=${DIR_OUT}/${BUILD_ID}_matrix_mutation_signature_summary.txt
CNA=${DIR_OUT}/${BUILD_ID}_matrix_CNA_summary_statistics.txt
python ${DIR_SCRIPTS}/synthesize_sample_matrix_results.py \
  -i ${MUT_COUNT},${CNA},${MUT_SIG},${MICRO} \
  -o ${DIR_OUT}/${BUILD_ID}_matrix_sample_summary.txt