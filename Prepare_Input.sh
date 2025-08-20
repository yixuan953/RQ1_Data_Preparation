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
# python /lustre/nobackup/WUR/ESG/zhou111/1_RQ1_Code/1_Data_Preparation/0_CreateListFile.py
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
# source /home/WUR/zhou111/miniconda3/etc/profile.d/conda.sh
# conda activate myenv
# python /lustre/nobackup/WUR/ESG/zhou111/1_RQ1_Code/1_Data_Preparation/2_CreatMask4S1.py
# conda deactivate

# 4 - Get the irrigation data
# module load cdo
# module load nco
# module load netcdf
crop_mask_dir="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_StudyArea"
process_dir="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/Process"

irrigated_ha="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/1_Global/Irrigation/MainCrop_Fraction_05d_lonlat.nc"
irrigation_amount="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/1_Global/Irrigation/maincrop_total_irrigation_amount.nc"

StudyAreas=("Rhine" "Yangtze" "LaPlata" "Indus")

Cut_HA(){
    for StudyArea in "${StudyAreas[@]}"; 
    do
        crop_mask="${crop_mask_dir}/${StudyArea}/Mask/${StudyArea}_maize_mask.nc"
        # The spatial range are the same for all crops. Here I use maize to cut irrigated HA as all of four study areas plant maize
        lat_min=$(ncdump -v lat $crop_mask | grep -oP "[-]?[0-9]+\.[0-9]+(?=,|\s)" | sort -n | head -n 1)
        lat_max=$(ncdump -v lat $crop_mask | grep -oP "[-]?[0-9]+\.[0-9]+(?=,|\s)" | sort -n | tail -n 1)
        lon_min=$(ncdump -v lon $crop_mask | grep -oP "[-]?[0-9]+\.[0-9]+(?=,|\s)" | sort -n | head -n 1)
        lon_max=$(ncdump -v lon $crop_mask | grep -oP "[-]?[0-9]+\.[0-9]+(?=,|\s)" | sort -n | tail -n 1)

        echo "Bounding box: lon=($lon_min, $lon_max), lat=($lat_min, $lat_max)"
        cdo sellonlatbox,$lon_min,$lon_max,$lat_min,$lat_max $irrigated_ha ${process_dir}/${StudyArea}_Irrigated_HA.nc
        cdo sellonlatbox,$lon_min,$lon_max,$lat_min,$lat_max $irrigation_amount ${process_dir}/${StudyArea}_maincrop_IrrAmount.nc
    done   
}
# Cut_HA

Divide_HA(){
    temp_file="${process_dir}/temp_rice_calc"
    irrigated_file="${process_dir}/Yangtze_Irrigated_HA.nc"
    secondrice_mask="${crop_mask_dir}/Yangtze/Mask/Yangtze_secondrice_mask.nc"

    cdo -O ifthen -selname,HA $secondrice_mask -selname,RICE_Irrigated_Area $irrigated_file ${temp_file}_secondrice_mask.nc

    # Calculate SECONDRICE_Irrigated_Area (half of RICE_Irrigated_Area where masked)
    cdo -O setmisstoc,0 -mulc,0.5 ${temp_file}_secondrice_mask.nc ${temp_file}_secondrice_area.nc

    # Calculate MAINRICE_Irrigated_Area (RICE_Irrigated_Area - SECONDRICE_Irrigated_Area)
    cdo -O setmisstoc,0 ${temp_file}_secondrice_area.nc ${temp_file}_secondrice_area_nomissing.nc
    cdo -O sub -selname,RICE_Irrigated_Area $irrigated_file ${temp_file}_secondrice_area_nomissing.nc ${temp_file}_mainrice_area.nc

    # Rename variables
    ncrename -v RICE_Irrigated_Area,SECONDRICE_Irrigated_Area ${temp_file}_secondrice_area.nc
    ncrename -v RICE_Irrigated_Area,MAINRICE_Irrigated_Area ${temp_file}_mainrice_area.nc

    ncatted -a units,SECONDRICE_Irrigated_Area,c,c,"ha" -a long_name,SECONDRICE_Irrigated_Area,c,c,"Irrigated area for second RICE" ${temp_file}_secondrice_area.nc
    ncatted -a units,MAINRICE_Irrigated_Area,c,c,"ha" -a long_name,MAINRICE_Irrigated_Area,c,c,"Irrigated area for main RICE" ${temp_file}_mainrice_area.nc

    # Merge the new variables into the original file
    ncks -A ${temp_file}_secondrice_area.nc $irrigated_file
    ncks -A ${temp_file}_mainrice_area.nc $irrigated_file

    # Clean up temporary files
    rm ${temp_file}*

    echo "Processing complete. New variables added to $irrigated_file"

}
# Divide_HA

Cal_Deficit(){
    source /home/WUR/zhou111/miniconda3/etc/profile.d/conda.sh
    conda activate myenv
    python /lustre/nobackup/WUR/ESG/zhou111/1_RQ1_Code/1_Data_Preparation/3_1_Cal_water_deficit.py
    conda deactivate
}
Cal_Deficit


# 5 - Cut the mask files

# 5 - Cut the fertilization and irrigation files