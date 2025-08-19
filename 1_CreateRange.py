from osgeo import gdal, ogr
import numpy as np
import xarray as xr
import os

input_dir = "/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_shp_StudyArea"
output_dir = "/lustre/nobackup/WUR/ESG/zhou111/2_RQ1_Data/2_StudyArea"
StudyAreas = ['LaPlata', 'Indus', 'Yangtze', 'Rhine']

res = 0.5  # degree resolution
xmin_global, xmax_global = -179.75, 179.75
ymax_global, ymin_global = 89.75, -89.75

for studyarea in StudyAreas:
    shp_file = os.path.join(input_dir, studyarea, f"{studyarea}.shp")
    out_nc = os.path.join(output_dir, studyarea, "range.nc")
    out_bbox = os.path.join(output_dir, studyarea, "bbox.txt")
    os.makedirs(os.path.dirname(out_nc), exist_ok=True)

    # Read shapefile
    shp = ogr.Open(shp_file)
    layer = shp.GetLayer()

    # Original extent
    xmin, xmax, ymin, ymax = layer.GetExtent()

    # Snap extent to the global 0.5° grid
    xmin = np.floor((xmin - xmin_global) / res) * res + xmin_global
    xmax = np.ceil((xmax - xmin_global) / res) * res + xmin_global
    ymin = np.floor((ymin - ymin_global) / res) * res + ymin_global
    ymax = np.ceil((ymax - ymin_global) / res) * res + ymin_global

    # Create lon/lat arrays
    lon = np.arange(xmin, xmax + 0.001, res)
    lat = np.arange(ymax, ymin - 0.001, -res)
    width, height = len(lon), len(lat)

    # Create in-memory raster
    target_ds = gdal.GetDriverByName('MEM').Create('', width, height, 1, gdal.GDT_Byte)
    transform = (xmin - res / 2, res, 0, ymax + res / 2, 0, -res)
    target_ds.SetGeoTransform(transform)
    target_ds.SetProjection(layer.GetSpatialRef().ExportToWkt())

    band = target_ds.GetRasterBand(1)
    band.Fill(0)

    # Rasterize
    gdal.RasterizeLayer(
        target_ds,
        [1],
        layer,
        burn_values=[1],
        options=["ALL_TOUCHED=TRUE"]
    )

    arr = band.ReadAsArray()

    # Save mask as NetCDF
    da = xr.DataArray(arr, coords=[('lat', lat), ('lon', lon)], name='mask')
    da['lat'].attrs = {'units': 'degrees_north', 'standard_name': 'latitude'}
    da['lon'].attrs = {'units': 'degrees_east', 'standard_name': 'longitude'}
    xr.Dataset({'mask': da}).to_netcdf(out_nc)

    # Save bounding box for CDO
    with open(out_bbox, 'w') as f:
        f.write(f"{xmin},{xmax},{ymin},{ymax}\n")

    print(f"{studyarea} -> {out_nc}")
    print(f"Bounding box saved: {xmin},{xmax},{ymin},{ymax}")




