import xarray as xr
import numpy as np



# Paths
input_file = "/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/1_Global/Fertilization/Return_ratio_05d.nc"
output_file = "/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/1_Global/Fertilization/Return_ratio_1981-2021.nc"

# Load dataset
ds = xr.open_dataset(input_file)

# Extract 1997 dataset
ds_1997 = ds.sel(year=1997)

# Create new years array for 1981-1996
new_years = np.arange(1981, 1997)

# Repeat 1997 dataset for 1981-1996
ds_1981_1996 = xr.concat([ds_1997]*len(new_years), dim='year')
ds_1981_1996 = ds_1981_1996.assign_coords(year=new_years)

# Concatenate with original dataset (1981-1996 first, then 1997-2021)
ds_extended = xr.concat([ds_1981_1996, ds], dim='year')

# Save to new NetCDF
ds_extended.to_netcdf(output_file)

print(f"Extended dataset saved to {output_file}")
