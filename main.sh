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
DIFF=`$SERVICE_DIR/jq -r '.diff' config.json`/dti/bin/b0.nii.gz
FSOP=`$SERVICE_DIR/jq -r '.freesurfer' config.json`

## set up paths and environment variables
SUBJ=output

MNI152=$FSLDIR/data/standard/MNI152_T1_1mm_brain.nii.gz
MNIMASK=$FSLDIR/data/standard/MNI152_T1_1mm_brain_mask.nii.gz

SUBJECTS_DIR=`pwd`
source $FREESURFER_HOME/SetUpFreeSurfer.sh

VOLDIR=$FSOP/mri

mkdir output

##
## convert labeled volumes into FS space and dt6 space
##

echo "Creating labeled freesurfer volumes..."

## aparc+aseg
mri_label2vol --seg $VOLDIR/aparc+aseg.mgz --temp $VOLDIR/aparc+aseg.mgz --regheader $VOLDIR/aparc+aseg.mgz --o ./output/aparc+aseg_full.nii.gz
mri_label2vol --seg $VOLDIR/aparc+aseg.mgz --temp $DIFF --regheader $VOLDIR/aparc+aseg.mgz --o ./output/aparc+aseg_anat.nii.gz

## aparc+a2009s+aseg
mri_label2vol --seg $VOLDIR/aparc.a2009s+aseg.mgz --temp $VOLDIR/aparc.a2009s+aseg.mgz --regheader $VOLDIR/aparc.a2009s+aseg.mgz --o ./output/aparc.a2009s+aseg_full.nii.gz
mri_label2vol --seg $VOLDIR/aparc.a2009s+aseg.mgz --temp $DIFF --regheader $VOLDIR/aparc.a2009s+aseg.mgz --o ./output/aparc.a2009s+aseg_anat.nii.gz

echo "Creating brain, white matter, and corpus callosum masks..."

## create brain masks
mri_binarize --i aparc+aseg_full.nii.gz --min 1 --o ./output/mask_full.nii.gz 
mri_binarize --i aparc+aseg_anat.nii.gz --min 1 --o ./output/mask_anat.nii.gz 

## create white matter masks
mri_binarize --i aparc+aseg_full.nii.gz --o ./output/wm_full.nii.gz --match 2 41 16 17 28 60 51 53 12 52 13 18 54 50 11 251 252 253 254 255 10 49 46 7
mri_binarize --i aparc+aseg_anat.nii.gz --o ./output/wm_anat.nii.gz --match 2 41 16 17 28 60 51 53 12 52 13 18 54 50 11 251 252 253 254 255 10 49 46 7

## create cc mask
mri_binarize --i aparc+aseg_full.nii.gz --o ./output/cc_full.nii.gz --match 251 252 253 254 255
mri_binarize --i aparc+aseg_anat.nii.gz --o ./output/cc_anat.nii.gz --match 251 252 253 254 255

echo "Performing linear alignment of labels to subject space..."

## convert brain.mgz to nifti for non-linear alignment
mri_vol2vol --mov $VOLDIR/brain.mgz --targ $DIFF --regheader --no-save-reg --o ./brain.nii.gz
fslmaths brain.nii.gz -bin ./brainmask.nii.gz

## compute linear alignment to MNI for atlas
flirt -in brain.nii.gz -ref $MNI152 -omat ./output/subj2mni.xfm

## create inverse linear transform
convert_xfm -omat ./output/mni2subj.xfm -inverse ./output/subj2mni.xfm

echo "Performing non-linear alignment of labels to subject space..."

## perform non-linear alignment to MNI space
fnirt --ref=$MNI152 --in=brain.nii.gz --refmask=$MNIMASK --inmask=brainmask.nii.gz --aff=./output/subj2mni.xfm --cout=./output/subj2mni_warps

## create inverse non-linear xform for MNI to subject space
invwarp --ref=brain.nii.gz --warp=./output/subj2mni_warps.nii.gz --out=./output/mni2subj_warps

echo "Aligning Shen278 atlas labels to subject space..."

## resample labels for test
applywarp -i $SERVICE_DIR/shen278_1mm.nii -r brain.nii.gz -o ./output/warped_shen278 --warp=./output/mni2subj_warps.nii.gz --interp=nn

## create inflated labels - blurs boundaries
#fslmaths ${SUBJ}_shen278.nii.gz -kernel box 2 -dilF ${SUBJ}_shen278_labels.nii.gz 

