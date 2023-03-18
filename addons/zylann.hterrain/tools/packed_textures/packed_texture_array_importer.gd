@tool
extends EditorImportPlugin

const HT_TextureLayeredImporter = preload("./texture_layered_importer.gd")
const HT_PackedTextureUtil = preload("./packed_texture_util.gd")
const HT_Errors = preload("../../util/errors.gd")
const HT_Result = preload("../util/result.gd")
const HT_Logger = preload("../../util/logger.gd")

const IMPORTER_NAME = "hterrain_packed_texture_array_importer"
const RESOURCE_TYPE = "TextureArray"

var _logger = HT_Logger.get_for(self)


func _get_importer_name() -> String:
	return IMPORTER_NAME


func _get_visible_name() -> String:
	# This shows up next to "Import As:"
	return "HTerrainPackedTextureArray"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["packed_texarr"])


func _get_save_extension() -> String:
	# Same as Godot's default TextureArray importer
	return "ctexarray"


func _get_resource_type() -> String:
	return RESOURCE_TYPE


func _get_preset_count() -> int:
	return 1


func _get_preset_name(preset_index: int) -> String:
	return ""


func _get_import_options(preset_index: int) -> Array:
	return [
		{
			"name": "compress/mode",
			"default_value": HT_TextureLayeredImporter.COMPRESS_VIDEO_RAM,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": HT_TextureLayeredImporter.COMPRESS_HINT_STRING
		},
		{
			"name": "flags/mipmaps",
			"default_value": true
		}
	]


func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	return true


func _import(p_source_path: String, p_save_path: String, options: Dictionary, 
	r_platform_variants: Array, r_gen_files: Array) -> int:

	var result := _import_internal(
		p_source_path, p_save_path, options, r_platform_variants, r_gen_files)
	
	if not result.success:
		_logger.error(result.get_message())
		# TODO Show detailed error in a popup if result is negative
	
	var code : int = result.value
	return code


func _import_internal(p_source_path: String, p_save_path: String, options: Dictionary, 
	r_platform_variants: Array, r_gen_files: Array) -> HT_Result:
	
	var f := FileAccess.open(p_source_path, File.READ)
	var err := FileAccess.get_open_error()
	if err != OK:
		return HT_Result.new(false, "Could not open file {0}: {1}" \
			.format([p_source_path, HT_Errors.get_message(err)])) \
			.with_value(err)
	var text := f.get_as_text()
	f = null
	
	var json = JSON.new()
	var json_err := json.parse(text)
	if json_err != OK:
		return HT_Result.new(false, "Failed to parse file {0}: {1}" \
			.format([p_source_path, json.get_error_message()])) \
			.with_value(json_err)
	var json_data : Dictionary = json.data
	
	var resolution : int = int(json_data.resolution)
	var contains_albedo : bool = json_data.get("contains_albedo", false)
	var layers : Array = json_data.get("layers")
	
	var images := []
	
	for layer_index in len(layers):
		var sources = layers[layer_index]
		var result = HT_PackedTextureUtil.generate_image(sources, resolution, _logger)

		if not result.success:
			return HT_Result.new(false, 
				"While importing layer {0}".format([layer_index]), result) \
				.with_value(result.value)
		
		var im : Image = result.value
		images.append(im)
	
	var result = HT_TextureLayeredImporter.import(
		p_source_path, 
		images, 
		p_save_path, 
		r_platform_variants, 
		r_gen_files, 
		contains_albedo,
		get_visible_name(),
		options["compress/mode"],
		options["flags/mipmaps"])
	
	if not result.success:
		return HT_Result.new(false, 
			"While importing {0}".format([p_source_path]), result) \
			.with_value(result.value)
	
	return HT_Result.new(true).with_value(OK)

