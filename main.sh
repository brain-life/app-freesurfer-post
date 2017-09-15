#!/bin/bash

[ "$PBS_O_WORKDIR" ] && cd $PBS_O_WORKDIR

if [ $ENV == "IUHPC" ]; then
    module load fsl/5.0.9
    module load freesurfer/6.0.0

    #[ $ENV == "CARBONATE" ] && module load singularity
fi

if [ $ENV == "VM" ]; then
    export FREESURFER_HOME=/usr/local/freesurfer
    source $FREESURFER_HOME/SetUpFreeSurfer.sh
fi

## grab the config.json inputs
DIFF=`$SERVICE_DIR/jq -r '.diff' config.json`
FSOP=`$SERVICE_DIR/jq -r '.freesurfer' config.json`

## set up paths and environment variables
SUBJ=output

MNI152=$FSLDIR/data/standard/MNI152_T1_1mm_brain.nii.gz
MNIMASK=$FSLDIR/data/standard/MNI152_T1_1mm_brain_mask.nii.gz

SUBJECTS_DIR=`pwd`
source $FREESURFER_HOME/SetUpFreeSurfer.sh

VOLDIR=$FSOP/mri

##
## convert labeled volumes into FS space and dt6 space
##

echo "Creating labeled freesurfer volumes..."

## aparc+aseg
mri_label2vol --seg $VOLDIR/aparc+aseg.mgz --temp $VOLDIR/aparc+aseg.mgz --regheader $VOLDIR/aparc+aseg.mgz --o aparc+aseg_full.nii.gz
mri_label2vol --seg $VOLDIR/aparc+aseg.mgz --temp $DIFF --regheader $VOLDIR/aparc+aseg.mgz --o aparc+aseg_anat.nii.gz

## aparc+a2009s+aseg
mri_label2vol --seg $VOLDIR/aparc.a2009s+aseg.mgz --temp $VOLDIR/aparc.a2009s+aseg.mgz --regheader $VOLDIR/aparc.a2009s+aseg.mgz --o aparc.a2009s+aseg_full.nii.gz
mri_label2vol --seg $VOLDIR/aparc.a2009s+aseg.mgz --temp $DIFF --regheader $VOLDIR/aparc.a2009s+aseg.mgz --o aparc.a2009s+aseg_anat.nii.gz

echo "Creating brain, white matter, and corpus callosum masks..."

## create brain masks
mri_binarize --i aparc+aseg_full.nii.gz --min 1 --o mask_full.nii.gz 
mri_binarize --i aparc+aseg_anat.nii.gz --min 1 --o mask_anat.nii.gz 

## create white matter masks
mri_binarize --i aparc+aseg_full.nii.gz --o wm_full.nii.gz --match 2 41 16 17 28 60 51 53 12 52 13 18 54 50 11 251 252 253 254 255 10 49 46 7
mri_binarize --i aparc+aseg_anat.nii.gz --o wm_anat.nii.gz --match 2 41 16 17 28 60 51 53 12 52 13 18 54 50 11 251 252 253 254 255 10 49 46 7

## create cc mask
mri_binarize --i aparc+aseg_full.nii.gz --o cc_full.nii.gz --match 251 252 253 254 255
mri_binarize --i aparc+aseg_anat.nii.gz --o cc_anat.nii.gz --match 251 252 253 254 255

echo "Performing linear alignment of labels to subject space..."

## convert brain.mgz to nifti for non-linear alignment
mri_vol2vol --mov $VOLDIR/brain.mgz --targ $DIFF --regheader --no-save-reg --o output/brain.nii.gz
fslmaths brain.nii.gz -bin brainmask.nii.gz

## compute linear alignment to MNI for atlas
flirt -in brain.nii.gz -ref $MNI152 -omat subj2mni.xfm

## create inverse linear transform
convert_xfm -omat mni2subj.xfm -inverse subj2mni.xfm

echo "Performing non-linear alignment of labels to subject space..."

## perform non-linear alignment to MNI space
fnirt --ref=$MNI152 --in=brain.nii.gz --refmask=$MNIMASK --inmask=brainmask.nii.gz --aff=subj2mni.xfm --cout=subj2mni_warps

## create inverse non-linear xform for MNI to subject space
invwarp --ref=brain.nii.gz --warp=subj2mni_warps.nii.gz --out=mni2subj_warps

echo "Aligning Shen278 atlas labels to subject space..."

## resample labels for test
applywarp -i ./shen278_1mm.nii -r brain.nii.gz -o ${SUBJ}_shen278 --warp=mni2subj_warps.nii.gz --interp=nn

## create inflated labels - blurs boundaries
#fslmaths output/${SUBJ}_shen278.nii.gz -kernel box 2 -dilF ${SUBJ}_shen278_labels.nii.gz 

