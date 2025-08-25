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

# =================================================================
# 1 - Get the range of the 4 basins and list files for S0
# source /home/WUR/zhou111/miniconda3/etc/profile.d/conda.sh
# conda activate myenv
# python /lustre/nobackup/WUR/ESG/zhou111/1_RQ1_Code/1_Data_Preparation/1_CreateRange.py
# conda deactivate

# =================================================================
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

# =================================================================
# 3 - Get the mask files containing TSUM1, TSUM2, Sow_date, and HA for for 4 basins  
# source /home/WUR/zhou111/miniconda3/etc/profile.d/conda.sh
# conda activate myenv
# python /lustre/nobackup/WUR/ESG/zhou111/1_RQ1_Code/1_Data_Preparation/2_CreatMask4S1.py
# conda deactivate

# =================================================================
# 4 - Get the irrigation data
# 4-1 Calculate the daily water deficit based on the resutls of S1 and upscale to monthly scale (1981 - 2016)
Cal_Deficit(){
    source /home/WUR/zhou111/miniconda3/etc/profile.d/conda.sh
    conda activate myenv
    python /lustre/nobackup/WUR/ESG/zhou111/1_RQ1_Code/1_Data_Preparation/3_Cal_water_deficit.py
    conda deactivate
}
# Cal_Deficit

# 4-2 Cut the original irrigation data for 4 basins, and divide the irrigated area for second rice in Yangtze River Basin
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

CutOriginalIrriData(){
    module load cdo
    module load nco
    module load netcdf
    crop_mask_dir="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_StudyArea"
    process_dir="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/Process"

    irrigated_ha="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/1_Global/Irrigation/MainCrop_Fraction_05d_lonlat.nc"
    irrigation_amount="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/1_Global/Irrigation/maincrop_irrigation_new.nc"

    StudyAreas=("Rhine" "Yangtze" "LaPlata" "Indus")
    Cut_HA
    # Divide_HA
}
# CutOriginalIrriData

# 4-3 Distribute irrigation water to each crop and calculate the irrigation rate
# module load cdo
# module load nco
# StudyAreas=("Rhine" "Yangtze" "LaPlata" "Indus")
# CropTypes=('mainrice' 'maize' 'secondrice' 'soybean' 'springwheat' 'winterwheat')
# Irrigation_dir="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/Process"
# Demand_dir="/lustre/nobackup/WUR/ESG/zhou111/3_RQ1_Model_Outputs/S1"
# process_dir="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/Process"
# output_dir="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_StudyArea"
# output_file="${output_dir}/${studyarea}/Irrigation/${studyarea}_${croptype}_monthly_Irri_Rate.nc"

Cal_Monthly_Irri_Demand(){

    for studyarea in "${StudyAreas[@]}"; do  

        irrigated_HA_file=${Irrigation_dir}/${studyarea}_Irrigated_HA.nc

        reference_timerange="-seldate,1981-01-01,2016-12-01"

        # Log missing crops
        log_file=$process_dir/${studyarea}_missing_crops.log
        echo "Missing crops for $studyarea (checked on $(date)):" > $log_file

        for croptype in "${CropTypes[@]}"; do
            # Select correct irrigated area variable
            if [ "$croptype" == "mainrice" ]; then
                if [ "$studyarea" == "Yangtze" ]; then
                    var_name="MAINRICE_Irrigated_Area"
                else
                    var_name="RICE_Irrigated_Area"
                fi
            elif [ "$croptype" == "secondrice" ]; then
                var_name="SECONDRICE_Irrigated_Area"
            elif [ "$croptype" == "winterwheat" ]; then
                var_name="WHEA_Irrigated_Area"
            elif [ "$croptype" == "soybean" ]; then
                var_name="SOYB_Irrigated_Area"
            elif [ "$croptype" == "maize" ]; then
                var_name="MAIZ_Irrigated_Area"
            fi

            # Skip crop if variable not in HA file
            if ! ncdump -h $irrigated_HA_file | grep -q "$var_name" ; then
                echo " - $croptype (no $var_name in irrigated_HA_file)" | tee -a $log_file
                continue
            fi

            # Deficit file (must exist)
            deficit_file=${Demand_dir}/${studyarea}_${croptype}_Deficit_monthly.nc
            if [ ! -f "$deficit_file" ]; then
                echo " - $croptype (deficit file missing: $deficit_file)" | tee -a $log_file
                continue
            fi

            # Cut deficit file to reference range
            if ! cdo $reference_timerange $deficit_file $process_dir/temp_${croptype}_deficit_timerange.nc; then
                echo " - $croptype (time range not in deficit file)" | tee -a $log_file
                continue
            fi

            # Extract HA variable (static, no time)
            cdo selvar,$var_name $irrigated_HA_file $process_dir/temp_${croptype}_Irri_HA.nc

            # Expand HA file to same timesteps as deficit file
            ntsteps=$(cdo ntime $process_dir/temp_${croptype}_deficit_timerange.nc)
            cdo duplicate,$ntsteps $process_dir/temp_${croptype}_Irri_HA.nc \
                $process_dir/temp_${croptype}_Irri_HA_timesteps.nc

            # Match timestamps from deficit file
            cdo showtimestamp $process_dir/temp_${croptype}_deficit_timerange.nc > $process_dir/temp_${croptype}_timestamps.txt
            sed 's/T/ /g; s/^[ \t]*//; s/[ \t]*$//' $process_dir/temp_${croptype}_timestamps.txt | tr -s ' ' '\n' | grep -v '^$' \
                > $process_dir/cleaned_${croptype}_timestamps.txt

            cat $process_dir/cleaned_${croptype}_timestamps.txt | \
                cdo -setdate,- $process_dir/temp_${croptype}_Irri_HA_timesteps.nc \
                $process_dir/temp_${croptype}_Irri_HA_timed.nc

            # Multiply deficit (WaterDeficit) by irrigated area
            cdo -O mul $process_dir/temp_${croptype}_deficit_timerange.nc \
                $process_dir/temp_${croptype}_Irri_HA_timed.nc \
                $process_dir/temp_result_${croptype}_multiply.nc

            # Rename variable to ${croptype}_Demand
            ncrename -v WaterDeficit,${croptype}_Demand $process_dir/temp_result_${croptype}_multiply.nc \
                $process_dir/${studyarea}_${croptype}_IrriDemand.nc

            # Add metadata
            ncatted -a units,${croptype}_Demand,m,c,"m3" \
                    -a long_name,${croptype}_Demand,m,c,"Monthly irrigation water demand for ${croptype}" \
                    $process_dir/${studyarea}_${croptype}_IrriDemand.nc

            # Clean temp files
            rm -f $process_dir/temp_${croptype}_*.nc \
                  $process_dir/temp_${croptype}_timestamps.txt \
                  $process_dir/cleaned_${croptype}_*.txt
        done

        # Remove empty log
        if [ $(wc -l < $log_file) -eq 1 ]; then
            rm -f $log_file
        fi

    done
}
# Cal_Monthly_Irri_Demand

Merge_Demand_And_Prop(){
    export HDF5_DISABLE_VERSION_CHECK=1

    for studyarea in "${StudyAreas[@]}"; do
        combined_file=$process_dir/${studyarea}_total_demand.nc
        prop_file=$process_dir/${studyarea}_IrriPro.nc

        # rm -f "$combined_file" "$prop_file"

        echo "Processing $studyarea ..."

        # Step 1: Merge all crop demand files
        first_crop=true
        for croptype in "${CropTypes[@]}"; do
            input_file=$process_dir/${studyarea}_${croptype}_IrriDemand.nc
            if [ ! -f "$input_file" ]; then
                echo " - Missing $input_file, skipping $croptype"
                continue
            fi

            if $first_crop; then
                cp "$input_file" "$combined_file"
                first_crop=false
            else
                ncks -A -v ${croptype}_Demand "$input_file" "$combined_file"
            fi
        done

        # Step 2: Compute Total_Demand robustly
        temp_total=$process_dir/temp_total.nc
        rm -f "$temp_total"

        first_sum=true
        total_crops_exist=false
        for croptype in "${CropTypes[@]}"; do
            if ncdump -h "$combined_file" | grep -q "${croptype}_Demand"; then
                total_crops_exist=true
                if $first_sum; then
                    cdo -O copy -selname,${croptype}_Demand "$combined_file" "$temp_total"
                    ncrename -v ${croptype}_Demand,Total_Demand "$temp_total"
                    first_sum=false
                else
                    cdo -O add "$temp_total" -selname,${croptype}_Demand "$combined_file" "$temp_total.tmp"
                    mv "$temp_total.tmp" "$temp_total"
                fi
            fi
        done

        # If no crops exist, create a zero Total_Demand
        if ! $total_crops_exist; then
            echo " - No crop variables found, creating zero Total_Demand"
            cdo -O setrtoc,0,0,0 "$combined_file" "$temp_total"
            ncrename -v $(ncdump -h "$combined_file" | grep "variables:" | awk '{print $2}' | head -1),Total_Demand "$temp_total"
        fi

        ncatted -a units,Total_Demand,c,c,"m3" \
                -a long_name,Total_Demand,c,c,"Total monthly irrigation water demand for all crops" \
                "$temp_total"

        ncks -A "$temp_total" "$combined_file"
        rm -f "$temp_total"

        # Step 3: Compute proportions safely
        for croptype in "${CropTypes[@]}"; do
            if ncdump -h "$combined_file" | grep -q "${croptype}_Demand"; then 

                # Select numerator (croptype demand) and denominator (total demand)
                cdo -O selname,${croptype}_Demand "$combined_file" "$process_dir/temp_num.nc"
                cdo -O selname,Total_Demand "$combined_file" "$process_dir/temp_den.nc"

                # Step 1: compute ratio (may create missings if Total_Demand=0)
                cdo -O div "$process_dir/temp_num.nc" "$process_dir/temp_den.nc" "$process_dir/temp_ratio.nc"

                # Step 2: Replace missings with 0
                cdo -O setmisstoc,0 "$process_dir/temp_ratio.nc" "$process_dir/temp_${croptype}_prop.nc"

                # Step 3: Rename variable to *_Proportion
                ncrename -v ${croptype}_Demand,${croptype}_Proportion "$process_dir/temp_${croptype}_prop.nc"

                # Step 4: Add attributes
                ncatted -a units,${croptype}_Proportion,c,c,"fraction" \
                        -a long_name,${croptype}_Proportion,c,c,"Proportion of total irrigation demand for ${croptype}" \
                        "$process_dir/temp_${croptype}_prop.nc"

                # Step 5: Append to final prop file
                ncks -A "$process_dir/temp_${croptype}_prop.nc" "$prop_file"

                # Clean up
                rm -f "$process_dir"/temp_*.nc
            fi
        done


        echo " --> Completed $studyarea"
        echo "     Total demand saved to $combined_file"
        echo "     Proportions saved to $prop_file"
    done
}
# Merge_Demand_And_Prop

GetIrriAmount(){
    for studyarea in "${StudyAreas[@]}"; do 
        irrigation_amount_original=${process_dir}/${studyarea}_maincrop_IrrAmount.nc
        ncks -d wu_class,0 $irrigation_amount_original $process_dir/temp_${studyarea}_maincrop_IrrAmount_MoveWUC.nc
        ncwa -a wu_class $process_dir/temp_${studyarea}_maincrop_IrrAmount_MoveWUC.nc $process_dir/${studyarea}_maincrop_IrrAmount_clean.nc
        Irri_Amount_File=$process_dir/${studyarea}_maincrop_IrrAmount_clean.nc

        Irri_Pro_File=$process_dir/${studyarea}_IrriPro.nc

        for croptype in "${CropTypes[@]}"; do 
            # Skip if proportion var does not exist
            if ! ncdump -h "$Irri_Pro_File" | grep -q "${croptype}_Proportion"; then
                echo "⚠️  ${croptype}_Demand not found in $Irri_Pro_File, skipping..."
                continue
            fi

            # Select proportion and calculate irrigation amount
            cdo selvar,${croptype}_Proportion $Irri_Pro_File $process_dir/temp_${studyarea}_${croptype}_Irri_Pro.nc
            cdo -O mul $Irri_Amount_File $process_dir/temp_${studyarea}_${croptype}_Irri_Pro.nc $process_dir/temp_${studyarea}_${croptype}_Monthly_IrrAmount.nc

            # Rename and add metadata
            ncrename -v MAIN_CROP_IRRIGATION,Irrigation_Amount $process_dir/temp_${studyarea}_${croptype}_Monthly_IrrAmount.nc $process_dir/Renamed_${studyarea}_${croptype}_Monthly_IrrAmount.nc
            ncatted -a units,Irrigation_Amount,m,c,"m3" \
                    -a long_name,Irrigation_Amount,m,c,"Monthly irrigation amount for ${croptype}" \
                    $process_dir/Renamed_${studyarea}_${croptype}_Monthly_IrrAmount.nc

            mv $process_dir/Renamed_${studyarea}_${croptype}_Monthly_IrrAmount.nc $output_dir/${studyarea}/Irrigation/${studyarea}_${croptype}_monthly_Irri_Amount.nc    
            echo "✅ Irrigation amount for $croptype in $studyarea is calculated and saved"

            rm -f $process_dir/temp_${studyarea}_${croptype}_Irri_Pro.nc \
                  $process_dir/temp_${studyarea}_${croptype}_Monthly_IrrAmount.nc
        done

        rm -f $process_dir/temp_${studyarea}_maincrop_IrrAmount_MoveWUC.nc \
              $process_dir/${studyarea}_maincrop_IrrAmount_clean.nc
    done
}
# GetIrriAmount

GetIrriRate(){  
    for studyarea in "${StudyAreas[@]}"; 
    do 
        HA_file=$process_dir/${studyarea}_Irrigated_HA.nc

        for croptype in "${CropTypes[@]}"; do 
            # Select irrigated HA variable name
            if [[ "$studyarea" == "Yangtze" && "$croptype" == "mainrice" ]]; then
                var_name="MAINRICE_Irrigated_Area"
            else
                case $croptype in
                    mainrice)    var_name="RICE_Irrigated_Area" ;;
                    secondrice)  var_name="SECONDRICE_Irrigated_Area" ;;
                    winterwheat) var_name="WHEA_Irrigated_Area" ;;
                    soybean)     var_name="SOYB_Irrigated_Area" ;;
                    maize)       var_name="MAIZ_Irrigated_Area" ;;
                esac
            fi

            # Skip if HA var does not exist
            if ! ncdump -h "$HA_file" | grep -q "$var_name"; then
                echo "⚠️  $var_name not found in $HA_file, skipping..."
                continue
            fi

            cdo selvar,$var_name $HA_file $process_dir/${studyarea}_${croptype}_Irrigated_HA.nc

            Irri_Amount=${output_dir}/${studyarea}/Irrigation/${studyarea}_${croptype}_monthly_Irri_Amount.nc
            nt=$(cdo ntime -selvar,Irrigation_Amount $Irri_Amount)

            # Duplicate HA to match time dimension
            cdo -O duplicate,$nt $process_dir/${studyarea}_${croptype}_Irrigated_HA.nc \
                                $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_bc.nc

            # Step 0: replace NaN in HA with 0
            cdo -O setmisstoc,0 $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_bc.nc \
                                $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_noNaN.nc

            # Step 1: safe HA for division (replace 0 with 1)
            cdo -O setrtoc,0,0,1 $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_noNaN.nc \
                                 $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_safe.nc

            # Step 2: divide Irrigation_Amount by safe HA and convert to mm
            cdo -O mulc,0.1 -div $Irri_Amount \
                                 $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_safe.nc \
                                 $process_dir/temp_${studyarea}_${croptype}_IrriRate_raw.nc

            # Step 3: create mask where HA>0
            cdo -O gtc,0 $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_noNaN.nc \
                           $process_dir/temp_${studyarea}_${croptype}_HA_mask.nc

            # Step 4: apply mask → sets Irrigation_Rate=0 where HA=0
            cdo -O mul $process_dir/temp_${studyarea}_${croptype}_IrriRate_raw.nc \
                         $process_dir/temp_${studyarea}_${croptype}_HA_mask.nc \
                         $process_dir/temp_${studyarea}_${croptype}_IrriRate_clean.nc

            # Rename variable and add attributes
            ncrename -v Irrigation_Amount,Irrigation_Rate $process_dir/temp_${studyarea}_${croptype}_IrriRate_clean.nc \
                                                           $process_dir/Renamed_${studyarea}_${croptype}_IrriRate.nc
            ncatted -a units,Irrigation_Rate,m,c,"mm" \
                    -a long_name,Irrigation_Rate,m,c,"Monthly irrigation rate for ${croptype}" \
                    $process_dir/Renamed_${studyarea}_${croptype}_IrriRate.nc

            # Move final file
            mv $process_dir/Renamed_${studyarea}_${croptype}_IrriRate.nc \
               $output_dir/${studyarea}/Irrigation/${studyarea}_${croptype}_monthly_Irri_Rate.nc    
            echo "✅ Irrigation rate for $croptype in $studyarea is calculated and saved"

            # Clean temporary files
            rm -f $process_dir/${studyarea}_${croptype}_Irrigated_HA.nc \
                  $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_bc.nc \
                  $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_noNaN.nc \
                  $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_safe.nc \
                  $process_dir/temp_${studyarea}_${croptype}_IrriRate_raw.nc \
                  $process_dir/temp_${studyarea}_${croptype}_HA_mask.nc \
                  $process_dir/temp_${studyarea}_${croptype}_IrriRate_clean.nc

        done
    done
}
# GetIrriRate


# =================================================================
# 5 - Cut the mask files
CutParaAdd2Mask(){
    for studyarea in Yangtze LaPlata Indus; do 
        paramfile="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/1_Global/NPParameters/All_parameters.nc"
        tmpfile="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/Process/tmp_${studyarea}.nc"
        bbox_file="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_StudyArea/${studyarea}/bbox.txt"
        bbox=$(cat "$bbox_file")       
        cdo -L sellonlatbox,$bbox "$paramfile" "$tmpfile"
        
        for maskfile in /lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_StudyArea/${studyarea}/Mask/${studyarea}_*mask.nc; do
            echo "Processing $maskfile ..."
            ncks -A "$tmpfile" "$maskfile"            
        done
    done
}
# CutParaAdd2Mask

# 6 - Cut the fertilization and irrigation files
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

# =================================================================
# 1 - Get the range of the 4 basins and list files for S0
# source /home/WUR/zhou111/miniconda3/etc/profile.d/conda.sh
# conda activate myenv
# python /lustre/nobackup/WUR/ESG/zhou111/1_RQ1_Code/1_Data_Preparation/1_CreateRange.py
# conda deactivate

# =================================================================
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

# =================================================================
# 3 - Get the mask files containing TSUM1, TSUM2, Sow_date, and HA for for 4 basins  
# source /home/WUR/zhou111/miniconda3/etc/profile.d/conda.sh
# conda activate myenv
# python /lustre/nobackup/WUR/ESG/zhou111/1_RQ1_Code/1_Data_Preparation/2_CreatMask4S1.py
# conda deactivate

# =================================================================
# 4 - Get the irrigation data
# 4-1 Calculate the daily water deficit based on the resutls of S1 and upscale to monthly scale (1981 - 2016)
Cal_Deficit(){
    source /home/WUR/zhou111/miniconda3/etc/profile.d/conda.sh
    conda activate myenv
    python /lustre/nobackup/WUR/ESG/zhou111/1_RQ1_Code/1_Data_Preparation/3_Cal_water_deficit.py
    conda deactivate
}
# Cal_Deficit

# 4-2 Cut the original irrigation data for 4 basins, and divide the irrigated area for second rice in Yangtze River Basin
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

CutOriginalIrriData(){
    module load cdo
    module load nco
    module load netcdf
    crop_mask_dir="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_StudyArea"
    process_dir="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/Process"

    irrigated_ha="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/1_Global/Irrigation/MainCrop_Fraction_05d_lonlat.nc"
    irrigation_amount="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/1_Global/Irrigation/maincrop_irrigation_new.nc"

    StudyAreas=("Rhine" "Yangtze" "LaPlata" "Indus")
    Cut_HA
    # Divide_HA
}
# CutOriginalIrriData

# 4-3 Distribute irrigation water to each crop and calculate the irrigation rate
# module load cdo
# module load nco
# StudyAreas=("Rhine" "Yangtze" "LaPlata" "Indus")
# CropTypes=('mainrice' 'maize' 'secondrice' 'soybean' 'springwheat' 'winterwheat')
# Irrigation_dir="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/Process"
# Demand_dir="/lustre/nobackup/WUR/ESG/zhou111/3_RQ1_Model_Outputs/S1"
# process_dir="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/Process"
# output_dir="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_StudyArea"
# output_file="${output_dir}/${studyarea}/Irrigation/${studyarea}_${croptype}_monthly_Irri_Rate.nc"

Cal_Monthly_Irri_Demand(){

    for studyarea in "${StudyAreas[@]}"; do  

        irrigated_HA_file=${Irrigation_dir}/${studyarea}_Irrigated_HA.nc

        reference_timerange="-seldate,1981-01-01,2016-12-01"

        # Log missing crops
        log_file=$process_dir/${studyarea}_missing_crops.log
        echo "Missing crops for $studyarea (checked on $(date)):" > $log_file

        for croptype in "${CropTypes[@]}"; do
            # Select correct irrigated area variable
            if [ "$croptype" == "mainrice" ]; then
                if [ "$studyarea" == "Yangtze" ]; then
                    var_name="MAINRICE_Irrigated_Area"
                else
                    var_name="RICE_Irrigated_Area"
                fi
            elif [ "$croptype" == "secondrice" ]; then
                var_name="SECONDRICE_Irrigated_Area"
            elif [ "$croptype" == "winterwheat" ]; then
                var_name="WHEA_Irrigated_Area"
            elif [ "$croptype" == "soybean" ]; then
                var_name="SOYB_Irrigated_Area"
            elif [ "$croptype" == "maize" ]; then
                var_name="MAIZ_Irrigated_Area"
            fi

            # Skip crop if variable not in HA file
            if ! ncdump -h $irrigated_HA_file | grep -q "$var_name" ; then
                echo " - $croptype (no $var_name in irrigated_HA_file)" | tee -a $log_file
                continue
            fi

            # Deficit file (must exist)
            deficit_file=${Demand_dir}/${studyarea}_${croptype}_Deficit_monthly.nc
            if [ ! -f "$deficit_file" ]; then
                echo " - $croptype (deficit file missing: $deficit_file)" | tee -a $log_file
                continue
            fi

            # Cut deficit file to reference range
            if ! cdo $reference_timerange $deficit_file $process_dir/temp_${croptype}_deficit_timerange.nc; then
                echo " - $croptype (time range not in deficit file)" | tee -a $log_file
                continue
            fi

            # Extract HA variable (static, no time)
            cdo selvar,$var_name $irrigated_HA_file $process_dir/temp_${croptype}_Irri_HA.nc

            # Expand HA file to same timesteps as deficit file
            ntsteps=$(cdo ntime $process_dir/temp_${croptype}_deficit_timerange.nc)
            cdo duplicate,$ntsteps $process_dir/temp_${croptype}_Irri_HA.nc \
                $process_dir/temp_${croptype}_Irri_HA_timesteps.nc

            # Match timestamps from deficit file
            cdo showtimestamp $process_dir/temp_${croptype}_deficit_timerange.nc > $process_dir/temp_${croptype}_timestamps.txt
            sed 's/T/ /g; s/^[ \t]*//; s/[ \t]*$//' $process_dir/temp_${croptype}_timestamps.txt | tr -s ' ' '\n' | grep -v '^$' \
                > $process_dir/cleaned_${croptype}_timestamps.txt

            cat $process_dir/cleaned_${croptype}_timestamps.txt | \
                cdo -setdate,- $process_dir/temp_${croptype}_Irri_HA_timesteps.nc \
                $process_dir/temp_${croptype}_Irri_HA_timed.nc

            # Multiply deficit (WaterDeficit) by irrigated area
            cdo -O mul $process_dir/temp_${croptype}_deficit_timerange.nc \
                $process_dir/temp_${croptype}_Irri_HA_timed.nc \
                $process_dir/temp_result_${croptype}_multiply.nc

            # Rename variable to ${croptype}_Demand
            ncrename -v WaterDeficit,${croptype}_Demand $process_dir/temp_result_${croptype}_multiply.nc \
                $process_dir/${studyarea}_${croptype}_IrriDemand.nc

            # Add metadata
            ncatted -a units,${croptype}_Demand,m,c,"m3" \
                    -a long_name,${croptype}_Demand,m,c,"Monthly irrigation water demand for ${croptype}" \
                    $process_dir/${studyarea}_${croptype}_IrriDemand.nc

            # Clean temp files
            rm -f $process_dir/temp_${croptype}_*.nc \
                  $process_dir/temp_${croptype}_timestamps.txt \
                  $process_dir/cleaned_${croptype}_*.txt
        done

        # Remove empty log
        if [ $(wc -l < $log_file) -eq 1 ]; then
            rm -f $log_file
        fi

    done
}
# Cal_Monthly_Irri_Demand

Merge_Demand_And_Prop(){
    export HDF5_DISABLE_VERSION_CHECK=1

    for studyarea in "${StudyAreas[@]}"; do
        combined_file=$process_dir/${studyarea}_total_demand.nc
        prop_file=$process_dir/${studyarea}_IrriPro.nc

        # rm -f "$combined_file" "$prop_file"

        echo "Processing $studyarea ..."

        # Step 1: Merge all crop demand files
        first_crop=true
        for croptype in "${CropTypes[@]}"; do
            input_file=$process_dir/${studyarea}_${croptype}_IrriDemand.nc
            if [ ! -f "$input_file" ]; then
                echo " - Missing $input_file, skipping $croptype"
                continue
            fi

            if $first_crop; then
                cp "$input_file" "$combined_file"
                first_crop=false
            else
                ncks -A -v ${croptype}_Demand "$input_file" "$combined_file"
            fi
        done

        # Step 2: Compute Total_Demand robustly
        temp_total=$process_dir/temp_total.nc
        rm -f "$temp_total"

        first_sum=true
        total_crops_exist=false
        for croptype in "${CropTypes[@]}"; do
            if ncdump -h "$combined_file" | grep -q "${croptype}_Demand"; then
                total_crops_exist=true
                if $first_sum; then
                    cdo -O copy -selname,${croptype}_Demand "$combined_file" "$temp_total"
                    ncrename -v ${croptype}_Demand,Total_Demand "$temp_total"
                    first_sum=false
                else
                    cdo -O add "$temp_total" -selname,${croptype}_Demand "$combined_file" "$temp_total.tmp"
                    mv "$temp_total.tmp" "$temp_total"
                fi
            fi
        done

        # If no crops exist, create a zero Total_Demand
        if ! $total_crops_exist; then
            echo " - No crop variables found, creating zero Total_Demand"
            cdo -O setrtoc,0,0,0 "$combined_file" "$temp_total"
            ncrename -v $(ncdump -h "$combined_file" | grep "variables:" | awk '{print $2}' | head -1),Total_Demand "$temp_total"
        fi

        ncatted -a units,Total_Demand,c,c,"m3" \
                -a long_name,Total_Demand,c,c,"Total monthly irrigation water demand for all crops" \
                "$temp_total"

        ncks -A "$temp_total" "$combined_file"
        rm -f "$temp_total"

        # Step 3: Compute proportions safely
        for croptype in "${CropTypes[@]}"; do
            if ncdump -h "$combined_file" | grep -q "${croptype}_Demand"; then 

                # Select numerator (croptype demand) and denominator (total demand)
                cdo -O selname,${croptype}_Demand "$combined_file" "$process_dir/temp_num.nc"
                cdo -O selname,Total_Demand "$combined_file" "$process_dir/temp_den.nc"

                # Step 1: compute ratio (may create missings if Total_Demand=0)
                cdo -O div "$process_dir/temp_num.nc" "$process_dir/temp_den.nc" "$process_dir/temp_ratio.nc"

                # Step 2: Replace missings with 0
                cdo -O setmisstoc,0 "$process_dir/temp_ratio.nc" "$process_dir/temp_${croptype}_prop.nc"

                # Step 3: Rename variable to *_Proportion
                ncrename -v ${croptype}_Demand,${croptype}_Proportion "$process_dir/temp_${croptype}_prop.nc"

                # Step 4: Add attributes
                ncatted -a units,${croptype}_Proportion,c,c,"fraction" \
                        -a long_name,${croptype}_Proportion,c,c,"Proportion of total irrigation demand for ${croptype}" \
                        "$process_dir/temp_${croptype}_prop.nc"

                # Step 5: Append to final prop file
                ncks -A "$process_dir/temp_${croptype}_prop.nc" "$prop_file"

                # Clean up
                rm -f "$process_dir"/temp_*.nc
            fi
        done


        echo " --> Completed $studyarea"
        echo "     Total demand saved to $combined_file"
        echo "     Proportions saved to $prop_file"
    done
}
# Merge_Demand_And_Prop

GetIrriAmount(){
    for studyarea in "${StudyAreas[@]}"; do 
        irrigation_amount_original=${process_dir}/${studyarea}_maincrop_IrrAmount.nc
        ncks -d wu_class,0 $irrigation_amount_original $process_dir/temp_${studyarea}_maincrop_IrrAmount_MoveWUC.nc
        ncwa -a wu_class $process_dir/temp_${studyarea}_maincrop_IrrAmount_MoveWUC.nc $process_dir/${studyarea}_maincrop_IrrAmount_clean.nc
        Irri_Amount_File=$process_dir/${studyarea}_maincrop_IrrAmount_clean.nc

        Irri_Pro_File=$process_dir/${studyarea}_IrriPro.nc

        for croptype in "${CropTypes[@]}"; do 
            # Skip if proportion var does not exist
            if ! ncdump -h "$Irri_Pro_File" | grep -q "${croptype}_Proportion"; then
                echo "⚠️  ${croptype}_Demand not found in $Irri_Pro_File, skipping..."
                continue
            fi

            # Select proportion and calculate irrigation amount
            cdo selvar,${croptype}_Proportion $Irri_Pro_File $process_dir/temp_${studyarea}_${croptype}_Irri_Pro.nc
            cdo -O mul $Irri_Amount_File $process_dir/temp_${studyarea}_${croptype}_Irri_Pro.nc $process_dir/temp_${studyarea}_${croptype}_Monthly_IrrAmount.nc

            # Rename and add metadata
            ncrename -v MAIN_CROP_IRRIGATION,Irrigation_Amount $process_dir/temp_${studyarea}_${croptype}_Monthly_IrrAmount.nc $process_dir/Renamed_${studyarea}_${croptype}_Monthly_IrrAmount.nc
            ncatted -a units,Irrigation_Amount,m,c,"m3" \
                    -a long_name,Irrigation_Amount,m,c,"Monthly irrigation amount for ${croptype}" \
                    $process_dir/Renamed_${studyarea}_${croptype}_Monthly_IrrAmount.nc

            mv $process_dir/Renamed_${studyarea}_${croptype}_Monthly_IrrAmount.nc $output_dir/${studyarea}/Irrigation/${studyarea}_${croptype}_monthly_Irri_Amount.nc    
            echo "✅ Irrigation amount for $croptype in $studyarea is calculated and saved"

            rm -f $process_dir/temp_${studyarea}_${croptype}_Irri_Pro.nc \
                  $process_dir/temp_${studyarea}_${croptype}_Monthly_IrrAmount.nc
        done

        rm -f $process_dir/temp_${studyarea}_maincrop_IrrAmount_MoveWUC.nc \
              $process_dir/${studyarea}_maincrop_IrrAmount_clean.nc
    done
}
# GetIrriAmount

GetIrriRate(){  
    for studyarea in "${StudyAreas[@]}"; 
    do 
        HA_file=$process_dir/${studyarea}_Irrigated_HA.nc

        for croptype in "${CropTypes[@]}"; do 
            # Select irrigated HA variable name
            if [[ "$studyarea" == "Yangtze" && "$croptype" == "mainrice" ]]; then
                var_name="MAINRICE_Irrigated_Area"
            else
                case $croptype in
                    mainrice)    var_name="RICE_Irrigated_Area" ;;
                    secondrice)  var_name="SECONDRICE_Irrigated_Area" ;;
                    winterwheat) var_name="WHEA_Irrigated_Area" ;;
                    soybean)     var_name="SOYB_Irrigated_Area" ;;
                    maize)       var_name="MAIZ_Irrigated_Area" ;;
                esac
            fi

            # Skip if HA var does not exist
            if ! ncdump -h "$HA_file" | grep -q "$var_name"; then
                echo "⚠️  $var_name not found in $HA_file, skipping..."
                continue
            fi

            cdo selvar,$var_name $HA_file $process_dir/${studyarea}_${croptype}_Irrigated_HA.nc

            Irri_Amount=${output_dir}/${studyarea}/Irrigation/${studyarea}_${croptype}_monthly_Irri_Amount.nc
            nt=$(cdo ntime -selvar,Irrigation_Amount $Irri_Amount)

            # Duplicate HA to match time dimension
            cdo -O duplicate,$nt $process_dir/${studyarea}_${croptype}_Irrigated_HA.nc \
                                $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_bc.nc

            # Step 0: replace NaN in HA with 0
            cdo -O setmisstoc,0 $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_bc.nc \
                                $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_noNaN.nc

            # Step 1: safe HA for division (replace 0 with 1)
            cdo -O setrtoc,0,0,1 $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_noNaN.nc \
                                 $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_safe.nc

            # Step 2: divide Irrigation_Amount by safe HA and convert to mm
            cdo -O mulc,0.1 -div $Irri_Amount \
                                 $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_safe.nc \
                                 $process_dir/temp_${studyarea}_${croptype}_IrriRate_raw.nc

            # Step 3: create mask where HA>0
            cdo -O gtc,0 $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_noNaN.nc \
                           $process_dir/temp_${studyarea}_${croptype}_HA_mask.nc

            # Step 4: apply mask → sets Irrigation_Rate=0 where HA=0
            cdo -O mul $process_dir/temp_${studyarea}_${croptype}_IrriRate_raw.nc \
                         $process_dir/temp_${studyarea}_${croptype}_HA_mask.nc \
                         $process_dir/temp_${studyarea}_${croptype}_IrriRate_clean.nc

            # Rename variable and add attributes
            ncrename -v Irrigation_Amount,Irrigation_Rate $process_dir/temp_${studyarea}_${croptype}_IrriRate_clean.nc \
                                                           $process_dir/Renamed_${studyarea}_${croptype}_IrriRate.nc
            ncatted -a units,Irrigation_Rate,m,c,"mm" \
                    -a long_name,Irrigation_Rate,m,c,"Monthly irrigation rate for ${croptype}" \
                    $process_dir/Renamed_${studyarea}_${croptype}_IrriRate.nc

            # Move final file
            mv $process_dir/Renamed_${studyarea}_${croptype}_IrriRate.nc \
               $output_dir/${studyarea}/Irrigation/${studyarea}_${croptype}_monthly_Irri_Rate.nc    
            echo "✅ Irrigation rate for $croptype in $studyarea is calculated and saved"

            # Clean temporary files
            rm -f $process_dir/${studyarea}_${croptype}_Irrigated_HA.nc \
                  $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_bc.nc \
                  $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_noNaN.nc \
                  $process_dir/temp_${studyarea}_${croptype}_Irrigated_HA_safe.nc \
                  $process_dir/temp_${studyarea}_${croptype}_IrriRate_raw.nc \
                  $process_dir/temp_${studyarea}_${croptype}_HA_mask.nc \
                  $process_dir/temp_${studyarea}_${croptype}_IrriRate_clean.nc

        done
    done
}
# GetIrriRate


# =================================================================
# 5 - Cut the mask files
CutParaAdd2Mask(){
    for studyarea in Yangtze LaPlata Indus; do 
        paramfile="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/1_Global/NPParameters/All_parameters.nc"
        tmpfile="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/Process/tmp_${studyarea}.nc"
        bbox_file="/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_StudyArea/${studyarea}/bbox.txt"
        bbox=$(cat "$bbox_file")       
        cdo -L sellonlatbox,$bbox "$paramfile" "$tmpfile"
        
        for maskfile in /lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_StudyArea/${studyarea}/Mask/${studyarea}_*mask.nc; do
            echo "Processing $maskfile ..."
            ncks -A "$tmpfile" "$maskfile"            
        done
    done
}
# CutParaAdd2Mask

# 6 - Create the fertilization files for 4 basins
# 6-1: Merge the fertilization 
MergeGlobalFert(){
    source /home/WUR/zhou111/miniconda3/etc/profile.d/conda.sh
    conda activate myenv
    python /lustre/nobackup/WUR/ESG/zhou111/1_RQ1_Code/1_Data_Preparation/6_1_Merge_GlobalFert.py
    conda deactivate
}
MergeGlobalFert

CutFertFiles(){
    source /home/WUR/zhou111/miniconda3/etc/profile.d/conda.sh
    conda activate myenv
    python /lustre/nobackup/WUR/ESG/zhou111/1_RQ1_Code/1_Data_Preparation/6_2_Cut_Fert.py
    conda deactivate    
}
CutFertFiles