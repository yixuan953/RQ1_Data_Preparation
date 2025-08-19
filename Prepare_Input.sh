#!/bin/bash
#-----------------------------Mail address-----------------------------

#-----------------------------Output files-----------------------------
#SBATCH --output=HPCReport/output_%j.txt
#SBATCH --error=HPCReport/error_output_%j.txt

#-----------------------------Required resources-----------------------
#SBATCH --time=600
#SBATCH --mem=250000

#--------------------Environment, Operations and Job steps-------------

# Create list files using excel
# source /home/WUR/zhou111/miniconda3/etc/profile.d/conda.sh
# conda activate myenv
# python /lustre/nobackup/WUR/ESG/zhou111/1_RQ1_Code/1_Data_Preparation/1_CreateListFile.p
# conda deactivate

# 1 - Get the range of the 4 basins and list files for S0
# source /home/WUR/zhou111/miniconda3/etc/profile.d/conda.sh
# conda activate myenv
# python /lustre/nobackup/WUR/ESG/zhou111/1_RQ1_Code/1_Data_Preparation/1_CreateRange.py
# conda deactivate

# 2 - Cut the meteodata and mask files
CutMeteoMask(){

    meteo_dir="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/1_Global/Meteo"
    mask_dir="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/1_Global/Masks"

    areas=("Yangtze" "Indus" "LaPlata" "Rhine")

    for area in "${areas[@]}"; do
        echo "=== Processing $area ==="

        range_file="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_StudyArea/${area}/range.nc"
        bbox_file="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_StudyArea/${area}/bbox.txt"
        bbox=$(cat "$bbox_file")

        meteo_out="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_StudyArea/${area}/Meteo"
        mask_out="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_StudyArea/${area}/Mask"
        mkdir -p "$meteo_out" "$mask_out"

        # === Meteo ===
        for file in "$meteo_dir"/*.nc; do
            inname=$(basename "$file")
            outname=$(echo "$inname" | sed -E 's/_[0-9]{4}-[0-9]{4}//')
            echo "  Meteo: $inname -> $outname"

            # 1. Cut to bounding box
            cdo -L sellonlatbox,$bbox "$file" tmp.nc

            # 2. Apply mask
            cdo -L ifthen "$range_file" -seldate,1981-01-01,2019-12-31 tmp.nc "${meteo_out}/${outname}"

            rm -f tmp.nc
        done

        # === Mask ===
        for file in "$mask_dir"/*.nc; do
            inname=$(basename "$file")
            outname=$(echo "$inname" | sed -E 's/_[0-9]{4}-[0-9]{4}//')
            echo "  Mask: $inname -> $outname"

            # 1. Cut to bounding box
            cdo -L sellonlatbox,$bbox "$file" tmp.nc

            # 2. Apply mask (keep only HA variable)
            cdo -L ifthen "$range_file" -selvar,HA tmp.nc "${mask_out}/${outname}"

            rm -f tmp.nc
        done

    done

    echo "All done!"
}
# CutMeteoMask

# 3 - Get the mask files containing TSUM1, TSUM2, Sow_date, and HA for for 4 basins  
source /home/WUR/zhou111/miniconda3/etc/profile.d/conda.sh
conda activate myenv
python /lustre/nobackup/WUR/ESG/zhou111/1_RQ1_Code/1_Data_Preparation/2_CreatMask4S1.py
conda deactivate

# conda deactivate

# 3 - Get the irrigation data

# 4 - Cut the mask files

# 5 - Cut the fertilization and irrigation files