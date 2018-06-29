module OsLib_Geometry

  # lower z value of vertices with starting value above x to new value of y
  def OsLib_Geometry.lowerSurfaceZvalue(surfaceArray, zValueTarget)

    counter = 0

    # loop over all surfaces
    surfaceArray.each do |surface|

      # create a new set of vertices
      newVertices = OpenStudio::Point3dVector.new

      # get the existing vertices for this interior partition
      vertices = surface.vertices
      flag = false
      vertices.each do |vertex|

        # initialize new vertex to old vertex
        x = vertex.x
        y = vertex.y
        z = vertex.z

        # if this z vertex is not on the z = 0 plane
        if z > zValueTarget
          z = zValueTarget
          flag = true
        end

        # add point to new vertices
        newVertices << OpenStudio::Point3d.new(x,y,z)
      end

      # set vertices to new vertices
      surface.setVertices(newVertices) #todo check if this was made, and issue warning if it was not. Could happen if resulting surface not planer.

      if flag then counter += 1 end

    end

    result = counter
    return result

  end

  # return an array of z values for surfaces passed in. The values will be relative to the parent origin. This was intended for spaces.
  def OsLib_Geometry.getSurfaceZValues(surfaceArray)

    zValueArray = []

    # loop over all surfaces
    surfaceArray.each do |surface|
      # get the existing vertices
      vertices = surface.vertices
      vertices.each do |vertex|
        # push z value to array
        zValueArray << vertex.z
      end
    end

    result = zValueArray
    return result

  end

  def OsLib_Geometry.createPointAtCenterOfFloor(model,space,zOffset)

    #find floors
    floors = []
    space.surfaces.each do |surface|
      next if not surface.surfaceType == "Floor"
      floors << surface
    end

    #this method only works for flat (non-inclined) floors
    boundingBox = OpenStudio::BoundingBox.new
    floors.each do |floor|
      boundingBox.addPoints(floor.vertices)
    end
    xmin = boundingBox.minX.get
    ymin = boundingBox.minY.get
    zmin = boundingBox.minZ.get
    xmax = boundingBox.maxX.get
    ymax = boundingBox.maxY.get

    x_pos = (xmin + xmax) / 2
    y_pos = (ymin + ymax) / 2
    z_pos = zmin + zOffset

    floorSurfacesInSpace = []
    space.surfaces.each do |surface|
      if surface.surfaceType == "Floor"
        floorSurfacesInSpace << surface
      end
    end

    pointIsOnFloor = OsLib_Geometry.checkIfPointIsOnSurfaceInArray(OpenStudio::Point3d.new(x_pos, y_pos, zmin),floorSurfacesInSpace)

    if pointIsOnFloor
      new_point = OpenStudio::Point3d.new(x_pos, y_pos, z_pos)
    else
      # don't make point, it doesn't appear to be inside of the space
      new_point = nil
    end

    result = new_point
    return result

  end

  def OsLib_Geometry.createPointInFromSubSurfaceAtSpecifiedHeight(model,subSurface,referenceFloor,distanceInFromWindow,heightAboveBottomOfSubSurface)

    window_outward_normal = subSurface.outwardNormal
    window_centroid = OpenStudio::getCentroid(subSurface.vertices).get
    window_outward_normal.setLength(distanceInFromWindow)
    vertex = window_centroid + window_outward_normal.reverseVector
    vertex_on_floorplane = referenceFloor.plane.project(vertex)
    floor_outward_normal = referenceFloor.outwardNormal
    floor_outward_normal.setLength(heightAboveBottomOfSubSurface)

    floorSurfacesInSpace = []
    subSurface.space.get.surfaces.each do |surface|
      if surface.surfaceType == "Floor"
        floorSurfacesInSpace << surface
      end
    end

    pointIsOnFloor = OsLib_Geometry.checkIfPointIsOnSurfaceInArray(vertex_on_floorplane,floorSurfacesInSpace)

    if pointIsOnFloor
      new_point = vertex_on_floorplane + floor_outward_normal.reverseVector
    else
      # don't make point, it doesn't appear to be inside of the space
      new_point = vertex_on_floorplane + floor_outward_normal.reverseVector #nil
    end

    result = new_point
    return result

  end

  def OsLib_Geometry.checkIfPointIsOnSurfaceInArray(point,surfaceArray)

    onSurfacesFlag = false

    surfaceArray.each do |surface|
      # Check if sensor is on floor plane (I need to loop through all floors)
      plane = surface.plane
      point_on_plane = plane.project(point)

      faceTransform = OpenStudio::Transformation::alignFace(surface.vertices)
      faceVertices = faceTransform*surface.vertices
      facePointOnPlane = faceTransform*point_on_plane

      if OpenStudio::pointInPolygon(facePointOnPlane, faceVertices.reverse, 0.01)
        # initial_sensor location lands in this surface's polygon
        onSurfacesFlag = true
      end

    end

    if onSurfacesFlag
      result = true
    else
      result = false
    end

    return result
  end

  def OsLib_Geometry.getExteriorWindowToWallRatio(spaceArray)

    # counters
    total_gross_ext_wall_area = 0
    total_ext_window_area = 0

    spaceArray.each do |space|

      #get surface area adjusting for zone multiplier
      zone = space.thermalZone
      if not zone.empty?
        zone_multiplier = zone.get.multiplier
        if zone_multiplier > 1
        end
      else
        zone_multiplier = 1 #space is not in a thermal zone
      end

      space.surfaces.each do |s|
        next if not s.surfaceType == "Wall"
        next if not s.outsideBoundaryCondition == "Outdoors"

        surface_gross_area = s.grossArea * zone_multiplier

        #loop through sub surfaces and add area including multiplier
        ext_window_area = 0
        s.subSurfaces.each do |subSurface|
          ext_window_area = ext_window_area + subSurface.grossArea * subSurface.multiplier * zone_multiplier
        end

        total_gross_ext_wall_area += surface_gross_area
        total_ext_window_area += ext_window_area
      end
    end

    if total_gross_ext_wall_area > 0
      result = total_ext_window_area/total_gross_ext_wall_area
    else
      result = 0.0 # todo - this should not happen if the building has geometry
    end

    return result

  end

  # create core and perimeter polygons from length width and origin
  def OsLib_Geometry.make_core_and_perimeter_polygons(runner,length,width,footprint_origin = OpenStudio::Point3d.new(0,0,0),perimeter_zone_depth = OpenStudio.convert(15,"ft","m").get)

    hash_of_point_vectors = {} # key is name, value is a hash, one item of which is polygon. Another could be space type

    #determine if core and perimeter zoning can be used
    if not length > perimeter_zone_depth * 2.5 && width > perimeter_zone_depth * 2.5
      perimeter_zone_depth = 0 #if any size is to small then just model floor as single zone, issue warning
      runner.registerWarning("Due to the size of the building modeling each floor as a single zone.")
    end

    x_delta = footprint_origin.x - length/2.0
    y_delta = footprint_origin.y - width/2.0
    z = 0
    nw_point = OpenStudio::Point3d.new(x_delta,y_delta+width,z)
    ne_point = OpenStudio::Point3d.new(x_delta+length,y_delta+width,z)
    se_point = OpenStudio::Point3d.new(x_delta+length,y_delta,z)
    sw_point = OpenStudio::Point3d.new(x_delta,y_delta,z)

    #Define polygons for a rectangular building
    if perimeter_zone_depth > 0
      perimeter_nw_point = nw_point + OpenStudio::Vector3d.new(perimeter_zone_depth,-perimeter_zone_depth,0)
      perimeter_ne_point = ne_point + OpenStudio::Vector3d.new(-perimeter_zone_depth,-perimeter_zone_depth,0)
      perimeter_se_point = se_point + OpenStudio::Vector3d.new(-perimeter_zone_depth,perimeter_zone_depth,0)
      perimeter_sw_point = sw_point + OpenStudio::Vector3d.new(perimeter_zone_depth,perimeter_zone_depth,0)

      west_polygon = OpenStudio::Point3dVector.new
      west_polygon << sw_point
      west_polygon << nw_point
      west_polygon << perimeter_nw_point
      west_polygon << perimeter_sw_point
      hash_of_point_vectors['West Perimeter Space'] = {}
      hash_of_point_vectors['West Perimeter Space'][:space_type] = nil # other methods being used by makeSpacesFromPolygons may have space types associated with each polygon but this doesn't.
      hash_of_point_vectors['West Perimeter Space'][:polygon] = west_polygon

      north_polygon = OpenStudio::Point3dVector.new
      north_polygon << nw_point
      north_polygon << ne_point
      north_polygon << perimeter_ne_point
      north_polygon << perimeter_nw_point
      hash_of_point_vectors['North Perimeter Space'] = {}
      hash_of_point_vectors['North Perimeter Space'][:space_type] = nil
      hash_of_point_vectors['North Perimeter Space'][:polygon] = north_polygon

      east_polygon = OpenStudio::Point3dVector.new
      east_polygon << ne_point
      east_polygon << se_point
      east_polygon << perimeter_se_point
      east_polygon << perimeter_ne_point
      hash_of_point_vectors['East Perimeter Space'] = {}
      hash_of_point_vectors['East Perimeter Space'][:space_type] = nil
      hash_of_point_vectors['East Perimeter Space'][:polygon] = east_polygon

      south_polygon = OpenStudio::Point3dVector.new
      south_polygon << se_point
      south_polygon << sw_point
      south_polygon << perimeter_sw_point
      south_polygon << perimeter_se_point
      hash_of_point_vectors['South Perimeter Space'] = {}
      hash_of_point_vectors['South Perimeter Space'][:space_type] = nil
      hash_of_point_vectors['South Perimeter Space'][:polygon] = south_polygon

      core_polygon = OpenStudio::Point3dVector.new
      core_polygon << perimeter_sw_point
      core_polygon << perimeter_nw_point
      core_polygon << perimeter_ne_point
      core_polygon << perimeter_se_point
      hash_of_point_vectors['Core Space'] = {}
      hash_of_point_vectors['Core Space'][:space_type] = nil
      hash_of_point_vectors['Core Space'][:polygon] = core_polygon

      # Minimal zones
    else
      whole_story_polygon = OpenStudio::Point3dVector.new
      whole_story_polygon << sw_point
      whole_story_polygon << nw_point
      whole_story_polygon << ne_point
      whole_story_polygon << se_point
      hash_of_point_vectors['Whole Story Space'] = {}
      hash_of_point_vectors['Whole Story Space'][:space_type] = nil
      hash_of_point_vectors['Whole Story Space'][:polygon] = whole_story_polygon
    end

    return hash_of_point_vectors
  end

  # sliced bar multi creates and array of multiple sliced bar simple hashes
  def OsLib_Geometry.make_sliced_bar_multi_polygons(runner,space_types,length,width,footprint_origin = OpenStudio::Point3d.new(0,0,0),story_hash)

    # total building floor area to calculate ratios from space type floor areas
    total_floor_area = 0.0
    target_per_space_type = {}
    space_types.each do |space_type, space_type_hash|
      total_floor_area += space_type_hash[:floor_area]
      target_per_space_type[space_type] = space_type_hash[:floor_area]
    end

    # sort array by floor area, this hash will be altered to reduce floor area for each space type to 0
    space_types_running_count = space_types.sort_by { |k, v| v[:floor_area] }

    # array entry for each story
    footprints = []

    # variables for sliver check
    valid_bar_width_min = OpenStudio.convert(3,"ft","m").get # re-evaluate what this should be
    bar_length = width # building width
    valid_bar_area_min = valid_bar_width_min * bar_length

    # loop through stories to populate footprints
    story_hash.each_with_index do |(k,v),i|

      # update the length and width for partial floors
      if i + 1 == story_hash.size
        area_multiplier = v[:partial_story_multiplier]
        edge_multiplier = Math.sqrt(area_multiplier)
        length = length * edge_multiplier
        width = width * edge_multiplier
      end

      # this will be populated for each building story
      target_footprint_area = v[:multiplier] * length * width
      current_footprint_area = 0.0
      space_types_local_count = {}

      space_types_running_count.each do |space_type,space_type_hash|

        # next if floor area is full or space type is empty
        next if current_footprint_area >= target_footprint_area
        next if space_type_hash[:floor_area] <= 0.0

        # special test for when total floor area is smaller than valid_bar_area_min, just make bar smaller that valid min and warn user
        if target_per_space_type[space_type] < valid_bar_area_min
          sliver_override = true
          runner.registerWarning("Floor area of #{space_type.name} results in a bar with smaller than target minimum width.")
        else
          sliver_override = false
        end

        # add entry for space type if it doesn't have one yet
        if not space_types_local_count.has_key?(space_type)
          space_types_local_count[space_type] = {:floor_area => 0.0}
        end

        # if there is enough of this space type to fill rest of floor area
        remaining_in_footprint = target_footprint_area - current_footprint_area
        if space_type_hash[:floor_area] > remaining_in_footprint

          # add to local count for story and remove from running count from space type
          raw_footprint_area_used = remaining_in_footprint

        else
          # if not then use up the rest of the floor area and move on to next space type
          raw_footprint_area_used = space_type_hash[:floor_area]
        end

        # add to local hash
        space_types_local_count[space_type][:floor_area] = raw_footprint_area_used / v[:multiplier].to_f

        # adjust balance ot running and local counts
        current_footprint_area += raw_footprint_area_used
        space_type_hash[:floor_area] -= raw_footprint_area_used

        # test if think slice left on current floor.
        # fix by moving smallest space type to next floor and and the same amount more of the sliver space type to this story
        if raw_footprint_area_used < valid_bar_area_min && sliver_override == false then test_a = true else test_a = false end

        # test if what would be left of the current space type would result in a sliver on the next story.
        # fix by removing some of this space type so their is enough left for the next story, and replace the removed amount with the largest space type in the model
        if space_type_hash[:floor_area] < valid_bar_area_min and space_type_hash[:floor_area] > 0.0001 then test_b = true else test_b = false end

        # identify very small slices and re-arrange spaces to different stories to avoid this
        if test_a

          # get first/smallest space type to move to another story
          first_space = space_types_local_count.first

          # adjustments running counter for space type being removed from this story
          space_types_running_count.each do |k2,v2|
            next if not k2 == first_space[0]
            v2[:floor_area] += first_space[1][:floor_area] * v[:multiplier]
          end

          # adjust running count for current space type
          space_type_hash[:floor_area] -= first_space[1][:floor_area] * v[:multiplier]

          # add to local count for current space type
          space_types_local_count[space_type][:floor_area] += first_space[1][:floor_area]

          # remove from local count for removed space type
          space_types_local_count.shift

        elsif test_b

          # swap size
          swap_size = valid_bar_area_min * 5 # currently equal to default perimeter zone depth of 15'

          # adjust running count for current space type
          space_type_hash[:floor_area] += swap_size

          # remove from local count for current space type
          space_types_local_count[space_type][:floor_area] -= swap_size / v[:multiplier].to_f

          # adjust footprint used
          current_footprint_area -= swap_size

          # the next larger space type will be brought down to fill out the footprint without any additional code

        end

      end

      # creating footprint for story
      footprints << OsLib_Geometry.make_sliced_bar_simple_polygons(runner,space_types_local_count,length,width,footprint_origin)
    end

    return footprints

  end

  # sliced bar simple creates a single sliced bar for space types passed in
  # todo - look at length and width to adjust slicing direction
  def OsLib_Geometry.make_sliced_bar_simple_polygons(runner,space_types,length,width,footprint_origin = OpenStudio::Point3d.new(0,0,0),perimeter_zone_depth = OpenStudio.convert(15,"ft","m").get)

    hash_of_point_vectors = {} # key is name, value is a hash, one item of which is polygon. Another could be space type

    #determine if core and perimeter zoning can be used
    if not length > perimeter_zone_depth * 2.5 && width > perimeter_zone_depth * 2.5
      perimeter_zone_depth = 0 #if any size is to small then just model floor as single zone, issue warning
      runner.registerWarning("Not modeling core and perimeter zones for some portion of the model.")
    end

    x_delta = footprint_origin.x - length/2.0
    y_delta = footprint_origin.y - width/2.0
    z = 0
    # this represents the entire bar, not individual space type slices
    nw_point = OpenStudio::Point3d.new(x_delta,y_delta+width,z)
    sw_point = OpenStudio::Point3d.new(x_delta,y_delta,z)

    # total building floor area to calculate ratios from space type floor areas
    total_floor_area = 0.0
    space_types.each do |space_type, space_type_hash|
      total_floor_area += space_type_hash[:floor_area]
    end

    # sort array by floor area but shift largest object to front
    space_types = space_types.sort_by { |k, v| v[:floor_area] }
    space_types.insert(0,space_types.delete_at(space_types.size-1))

    # min and max bar end values
    min_bar_end_multiplier = 0.75
    max_bar_end_multiplier = 1.5

    # sort_by results in arrays with two items , first is key, second is hash value
    re_apply_largest_space_type_at_end = false
    max_reduction = nil # used when looping through section_hash_for_space_type if first space type needs to also be at far end of bar
    space_types.each do |space_type,space_type_hash|

      # setup end perimeter zones if needed
      start_perimeter_width_deduction = 0.0
      end_perimeter_width_deduction = 0.0
      if space_type == space_types.first[0]
        if length * space_type_hash[:floor_area]/total_floor_area > max_bar_end_multiplier * perimeter_zone_depth
          start_perimeter_width_deduction = perimeter_zone_depth
        end
        # see if last space type is too small for perimeter. If it is then save some of this space type
        if length * space_types.last[1][:floor_area]/total_floor_area < perimeter_zone_depth * min_bar_end_multiplier
          re_apply_largest_space_type_at_end = true
        end
      end
      if space_type == space_types.last[0]
        if length * space_type_hash[:floor_area]/total_floor_area > max_bar_end_multiplier * perimeter_zone_depth
          end_perimeter_width_deduction = perimeter_zone_depth
        end
      end
      non_end_adjusted_width = (length * space_type_hash[:floor_area]/total_floor_area) - start_perimeter_width_deduction - end_perimeter_width_deduction

      # adjustment of end space type is too small and is replaced with largest space type
      if space_type == space_types.first[0] and re_apply_largest_space_type_at_end
        max_reduction = [perimeter_zone_depth,non_end_adjusted_width].min
        non_end_adjusted_width -= max_reduction
      end
      if space_type == space_types.last[0] and re_apply_largest_space_type_at_end
        end_perimeter_width_deduction = space_types.first[0]
      end

      # poulate data for core and perimeter of slice
      section_hash_for_space_type = {}
      section_hash_for_space_type["end_a"] = start_perimeter_width_deduction
      section_hash_for_space_type[""] = non_end_adjusted_width
      section_hash_for_space_type["end_b"] = end_perimeter_width_deduction

      # loop through sections for space type (main and possibly one or two end perimeter sections)
      section_hash_for_space_type.each do |k,width|

        if width.class.to_s == "OpenStudio::Model::SpaceType" # confirm this
          space_type = width
          max_reduction = [perimeter_zone_depth,max_reduction].min
          width = max_reduction
        end
        if width == 0
          next
        end

        ne_point = nw_point + OpenStudio::Vector3d.new(width,0,0)
        se_point = sw_point + OpenStudio::Vector3d.new(width,0,0)

        if perimeter_zone_depth > 0
          polygon_a = OpenStudio::Point3dVector.new
          polygon_a << sw_point
          polygon_a << sw_point + OpenStudio::Vector3d.new(0,perimeter_zone_depth,0)
          polygon_a << se_point + OpenStudio::Vector3d.new(0,perimeter_zone_depth,0)
          polygon_a << se_point
          hash_of_point_vectors["#{space_type.name} A #{k}"] = {}
          hash_of_point_vectors["#{space_type.name} A #{k}"][:space_type] = space_type
          hash_of_point_vectors["#{space_type.name} A #{k}"][:polygon] = polygon_a

          polygon_b = OpenStudio::Point3dVector.new
          polygon_b << sw_point + OpenStudio::Vector3d.new(0,perimeter_zone_depth,0)
          polygon_b << nw_point + OpenStudio::Vector3d.new(0,- perimeter_zone_depth,0)
          polygon_b << ne_point + OpenStudio::Vector3d.new(0,- perimeter_zone_depth,0)
          polygon_b << se_point + OpenStudio::Vector3d.new(0,perimeter_zone_depth,0)
          hash_of_point_vectors["#{space_type.name} B #{k}"] = {}
          hash_of_point_vectors["#{space_type.name} B #{k}"][:space_type] = space_type
          hash_of_point_vectors["#{space_type.name} B #{k}"][:polygon] = polygon_b

          polygon_c = OpenStudio::Point3dVector.new
          polygon_c << nw_point + OpenStudio::Vector3d.new(0,- perimeter_zone_depth,0)
          polygon_c << nw_point
          polygon_c << ne_point
          polygon_c << ne_point + OpenStudio::Vector3d.new(0,- perimeter_zone_depth,0)
          hash_of_point_vectors["#{space_type.name} C #{k}"] = {}
          hash_of_point_vectors["#{space_type.name} C #{k}"][:space_type] = space_type
          hash_of_point_vectors["#{space_type.name} C #{k}"][:polygon] = polygon_c
        else
          polygon_a = OpenStudio::Point3dVector.new
          polygon_a << sw_point
          polygon_a << nw_point
          polygon_a << ne_point
          polygon_a << se_point
          hash_of_point_vectors["#{space_type.name} #{k}"] = {}
          hash_of_point_vectors["#{space_type.name} #{k}"][:space_type] = space_type
          hash_of_point_vectors["#{space_type.name} #{k}"][:polygon] = polygon_a
        end

        # update west points
        nw_point = ne_point
        sw_point = se_point

      end

    end

    return hash_of_point_vectors

  end

  # take diagram made by make_core_and_perimeter_polygons and make multi-story building
  # todo - add option to create shading surfaces when using multiplier. Mainly important for non rectangular buildings where self shading would be an issue
  def OsLib_Geometry.makeSpacesFromPolygons(runner,model,footprints,typical_story_height,effective_num_stories,footprint_origin = OpenStudio::Point3d.new(0,0,0),story_hash = {})

    # default story hash is for three stories with mid-story multiplier, but user can pass in custom versions
    if story_hash.empty?
      if effective_num_stories > 2
        story_hash['Ground'] = {:space_origin_z => footprint_origin.z,:space_height => typical_story_height, :multiplier => 1}
        story_hash['Mid'] = {:space_origin_z => footprint_origin.z + typical_story_height + typical_story_height * (effective_num_stories.ceil - 3) / 2.0,:space_height => typical_story_height, :multiplier => effective_num_stories - 2}
        story_hash['Top'] = {:space_origin_z => footprint_origin.z + typical_story_height * (effective_num_stories.ceil - 1),:space_height => typical_story_height, :multiplier => 1}
      elsif effective_num_stories > 1
        story_hash['Ground'] = {:space_origin_z => footprint_origin.z,:space_height => typical_story_height, :multiplier => 1}
        story_hash['Top'] = {:space_origin_z => footprint_origin.z + typical_story_height * (effective_num_stories.ceil - 1),:space_height => typical_story_height, :multiplier => 1}
      else # one story only
        story_hash['Ground'] = {:space_origin_z => footprint_origin.z,:space_height => typical_story_height, :multiplier => 1}
      end
    end

    # loop through story_hash and polygons to generate all of the spaces
    story_hash.each_with_index do |(story_name,story_data),index|

      # make new story
      story = OpenStudio::Model::BuildingStory.new(model)
      story.setNominalFloortoFloorHeight(story_data[:space_height]) # not used for anything
      story.setNominalZCoordinate (story_data[:space_origin_z]) # not used for anything
      story.setName("Story #{story_name}")

      # multiplier values for adjacent stories to be altered below as needed
      multiplier_story_above = 1
      multiplier_story_below = 1

      if index == 0 # bottom floor, only check above
        if story_hash.size > 1
          multiplier_story_above = story_hash.values[index + 1][:multiplier]
        end
      elsif index == story_hash.size - 1 # top floor, check only below
        multiplier_story_below = story_hash.values[index + -1][:multiplier]
      else # mid floor, check above and below
        multiplier_story_above = story_hash.values[index + 1][:multiplier]
        multiplier_story_below = story_hash.values[index + -1][:multiplier]
      end

      # if adjacent story has multiplier > 1 then make appropriate surfaces adiabatic
      adiabatic_ceilings = false
      adiabatic_floors = false
      if story_data[:multiplier] > 1
        adiabatic_ceilings = true
        adiabatic_floors = true
      elsif multiplier_story_above > 1
        adiabatic_ceilings = true
      elsif multiplier_story_below > 1
        adiabatic_floors = true
      end

      # get the right collection of polygons to make up footprint for each building story
      if index > footprints.size - 1
        # use last footprint
        target_footprint = footprints.last
      else
        target_footprint = footprints[index]
      end
      target_footprint.each do |name,space_data|

        # gather options
        options = {
            "name" => "#{name} - #{story.name}",
            "spaceType" => space_data[:space_type],
            "story" => story,
            "makeThermalZone" => true,
            "thermalZoneMultiplier" => story_data[:multiplier],
            "floor_to_floor_height" => story_data[:space_height],
        }

        # make space
        space = OsLib_Geometry.makeSpaceFromPolygon(model,space_data[:polygon].first,space_data[:polygon],options)

        # set z origin to proper position
        space.setZOrigin(story_data[:space_origin_z])

        # loop through celings and floors to hard asssign constructions and set boundary condition
        if adiabatic_ceilings or adiabatic_floors
          space.surfaces.each do |surface|
            if adiabatic_floors and surface.surfaceType == "Floor"
              if surface.construction.is_initialized
                surface.setConstruction(surface.construction.get)
              end
              surface.setOutsideBoundaryCondition("Adiabatic")
            end
            if adiabatic_ceilings and surface.surfaceType == "RoofCeiling"
              if surface.construction.is_initialized
                surface.setConstruction(surface.construction.get)
              end
              surface.setOutsideBoundaryCondition("Adiabatic")
            end
          end
        end

      end

      # todo - in future add code to include plenums or raised floor to each/any story.

    end

    # any changes to wall boundary conditions will be handled by same code that calls this method.
    # this method doesn't need to know about basements and party walls.

    return model
  end

  # add def to create a space from input, optionally take a name, space type, story and thermal zone.
  def OsLib_Geometry.makeSpaceFromPolygon(model,space_origin,point3dVector,options = {})

    # set defaults to use if user inputs not passed in
    defaults = {
        "name" => nil,
        "spaceType" => nil,
        "story" => nil,
        "makeThermalZone" => nil,
        "thermalZone" => nil,
        "thermalZoneMultiplier" => 1,
        "floor_to_floor_height" => OpenStudio::convert(10,"ft","m").get,
    }

    # merge user inputs with defaults
    options = defaults.merge(options)

    # Identity matrix for setting space origins
    m = OpenStudio::Matrix.new(4,4,0)
    m[0,0] = 1
    m[1,1] = 1
    m[2,2] = 1
    m[3,3] = 1

    # make space from floor print
    space = OpenStudio::Model::Space::fromFloorPrint(point3dVector, options["floor_to_floor_height"], model)
    space = space.get
    m[0,3] = space_origin.x
    m[1,3] = space_origin.y
    m[2,3] = space_origin.z
    space.changeTransformation(OpenStudio::Transformation.new(m))
    space.setBuildingStory(options["story"])
    if not options['name'].nil?
      space.setName(options['name'])
    end

    if not options["spaceType"].nil?
      space.setSpaceType(options["spaceType"])
    end

    # create thermal zone if requested and assign
    if options["makeThermalZone"]
      new_zone = OpenStudio::Model::ThermalZone.new(model)
      new_zone.setMultiplier(options["thermalZoneMultiplier"])
      space.setThermalZone(new_zone)
      new_zone.setName("Zone #{space.name}")
    else
      if not options["thermalZone"].nil? then space.setThermalZone(options["thermalZone"]) end
    end

    result = space
    return result

  end

  def OsLib_Geometry.getExteriorWindowAndWllAreaByOrientation(model, spaceArray, options = {})

    # set defaults to use if user inputs not passed in
    defaults = {
        "northEast" => 45,
        "southEast" => 125,
        "southWest" => 225,
        "northWest" => 315,
    }

    # merge user inputs with defaults
    options = defaults.merge(options)

    # counters
    total_gross_ext_wall_area_North = 0
    total_gross_ext_wall_area_South = 0
    total_gross_ext_wall_area_East = 0
    total_gross_ext_wall_area_West = 0
    total_ext_window_area_North = 0
    total_ext_window_area_South = 0
    total_ext_window_area_East = 0
    total_ext_window_area_West = 0

    spaceArray.each do |space|

      #get surface area adjusting for zone multiplier
      zone = space.thermalZone
      if not zone.empty?
        zone_multiplier = zone.get.multiplier
        if zone_multiplier > 1
        end
      else
        zone_multiplier = 1 #space is not in a thermal zone
      end

      space.surfaces.each do |s|
        next if not s.surfaceType == "Wall"
        next if not s.outsideBoundaryCondition == "Outdoors"

        surface_gross_area = s.grossArea * zone_multiplier

        #loop through sub surfaces and add area including multiplier
        ext_window_area = 0
        s.subSurfaces.each do |subSurface|
          ext_window_area = ext_window_area + subSurface.grossArea * subSurface.multiplier * zone_multiplier
        end

        absoluteAzimuth =  OpenStudio::convert(s.azimuth,"rad","deg").get + s.space.get.directionofRelativeNorth + model.getBuilding.northAxis
        until absoluteAzimuth < 360.0
          absoluteAzimuth = absoluteAzimuth - 360.0
        end

        # add to exterior wall counter if north or south
        if options["northEast"] <= absoluteAzimuth and absoluteAzimuth < options["southEast"]  # East exterior walls
          total_gross_ext_wall_area_East += surface_gross_area
          total_ext_window_area_East += ext_window_area
        elsif options["southEast"] <= absoluteAzimuth and absoluteAzimuth < options["southWest"] # South exterior walls
          total_gross_ext_wall_area_South += surface_gross_area
          total_ext_window_area_South += ext_window_area
        elsif options["southWest"] <= absoluteAzimuth and absoluteAzimuth < options["northWest"] # West exterior walls
          total_gross_ext_wall_area_West += surface_gross_area
          total_ext_window_area_West += ext_window_area
        else # North exterior walls
          total_gross_ext_wall_area_North += surface_gross_area
          total_ext_window_area_North += ext_window_area
        end

      end
    end

    result = {"northWall"=> total_gross_ext_wall_area_North,
              "northWindow"=> total_ext_window_area_North,
              "southWall"=> total_gross_ext_wall_area_South,
              "southWindow"=> total_ext_window_area_South,
              "eastWall"=> total_gross_ext_wall_area_East,
              "eastWindow"=> total_ext_window_area_East,
              "westWall"=> total_gross_ext_wall_area_West,
              "westWindow"=> total_ext_window_area_West,
    }
    return result

  end

  def OsLib_Geometry.getAbsoluteAzimuthForSurface(surface,model)
    absolute_azimuth =  OpenStudio::convert(surface.azimuth,"rad","deg").get + surface.space.get.directionofRelativeNorth + model.getBuilding.northAxis
    until absolute_azimuth < 360.0
      absolute_azimuth = absolute_azimuth - 360.0
    end
    return absolute_azimuth
  end

  # dont use this, use calculate_story_exterior_wall_perimeter instead
  def OsLib_Geometry.estimate_perimeter(perim_story)

    perimeter = 0
    perim_story.spaces.each do |space|
      space.surfaces.each do |surface|
        next if surface.outsideBoundaryCondition != "Outdoors" or  surface.surfaceType != "Wall"
        area = surface.grossArea
        z_value_array = OsLib_Geometry.getSurfaceZValues([surface])
        next if z_value_array.max == z_value_array.min # shouldn't see this unless wall is horizontal
        perimeter += area/(z_value_array.max - z_value_array.min)
      end
    end

    return perimeter
  end

  # calculate story perimeter. Selected story should have above grade walls. If not perimeter may return zero.
  # optional_multiplier_adjustment is used in special case when there are zone multipliers that represent additional zones within the same story
  # the value entered represents the story_multiplier which reduces the adjustment by that factor over the full zone multiplier
  # todo - this doesn't catch walls that are split that sit above floor surfaces that are not (e.g. main corridoor in secondary school model)
  # todo - also odd with multi-height spaces
  def OsLib_Geometry.calculate_story_exterior_wall_perimeter(runner, story,optional_multiplier_adjustment = nil,tested_wall_boundary_condition = ['Outdoors','Ground'],bounding_box = nil)

    perimeter = 0
    party_walls = []
    story.spaces.each do |space|
      # counter to use later
      edge_hash = {}
      edge_counter = 0
      space.surfaces.each do |surface|
        # get vertices
        vertex_hash = {}
        vertex_counter = 0
        surface.vertices.each do |vertex|
          vertex_counter += 1
          vertex_hash[vertex_counter] = [vertex.x,vertex.y,vertex.z]
        end
        # make edges
        counter = 0
        vertex_hash.each do |k,v|
          edge_counter += 1
          counter += 1
          if vertex_hash.size != counter
            edge_hash[edge_counter] = [v,vertex_hash[counter+1],surface,surface.outsideBoundaryCondition,surface.surfaceType]
          else # different code for wrap around vertex
            edge_hash[edge_counter] = [v,vertex_hash[1],surface,surface.outsideBoundaryCondition,surface.surfaceType]
          end
        end
      end

      # check edges for matches (need opposite vertices and proper boundary conditions)
      edge_hash.each do |k1,v1|
        # apply to any floor boundary condition. This supports used in floors above basements
        next if v1[4] != "Floor"
        edge_hash.each do |k2,v2|
          test_boundary_cond = false
          next if not tested_wall_boundary_condition.include?(v2[3]) # method arg takes multiple conditions
          next if v2[4] != "Wall"

          # see if edges have same geometry

          # found cases where the two lines below removed edges and resulted in lower than actual perimeter. Added new code with tolerance.
          #next if not v1[0] == v2[1] # next if not same geometry reversed
          #next if not v1[1] == v2[0]

          # these are three item array's add in tollerance for each array entry
          tolerance = 0.0001
          test_a = true
          test_b = true
          3.times.each do |i|
            if (v1[0][i] - v2[1][i]).abs > tolerance
              test_a = false
            end
            if (v1[1][i] - v2[0][i]).abs > tolerance
              test_b = false
            end
          end

          next if not test_a == true
          next if not test_b == true

          #edge_bounding_box = OpenStudio::BoundingBox.new
          #edge_bounding_box.addPoints(space.transformation() * v2[2].vertices)
          # if not edge_bounding_box.intersects(bounding_box) doesn't seem to work reliably, writing custom code to check

          point_one = OpenStudio::Point3d.new(v2[0][0],v2[0][1],v2[0][2])
          point_one = (space.transformation * point_one)
          point_two = OpenStudio::Point3d.new(v2[1][0],v2[1][1],v2[1][2])
          point_two = (space.transformation * point_two)

          if not bounding_box.nil? and v2[3] == "Adiabatic"

            on_bounding_box = false
            if (bounding_box.minX.to_f - point_one.x).abs < tolerance and (bounding_box.minX.to_f - point_two.x).abs < tolerance
              on_bounding_box = true
            elsif (bounding_box.maxX.to_f - point_one.x).abs < tolerance and (bounding_box.maxX.to_f - point_two.x).abs < tolerance
              on_bounding_box = true
            elsif (bounding_box.minY.to_f - point_one.y).abs < tolerance and (bounding_box.minY.to_f - point_two.y).abs < tolerance
              on_bounding_box = true
            elsif (bounding_box.maxY.to_f - point_one.y).abs < tolerance and (bounding_box.maxY.to_f - point_two.y).abs < tolerance
              on_bounding_box = true
            end

            # if not edge_bounding_box.intersects(bounding_box) doesn't seem to work reliably, writing custom code to check
            # todo - this is basic check for adiabatic party walls and won't catch all situations. Can be made more robust in the future
            if on_bounding_box == true
              length = OpenStudio::Vector3d.new(point_one - point_two).length
              party_walls << v2[2]
              length_ip_display = OpenStudio.convert(length,'m','ft').get.round(2)
              runner.registerInfo(" * #{v2[2].name} has an adiabatic boundary condition and sits in plane with the building bounding box. Adding #{length_ip_display} (ft) to perimeter length of #{story.name} for this surface, assuming it is a party wall.")
            elsif space.multiplier == 1
              length = OpenStudio::Vector3d.new(point_one - point_two).length
              party_walls << v2[2]
              length_ip_display = OpenStudio.convert(length,'m','ft').get.round(2)
              runner.registerInfo(" * #{v2[2].name} has an adiabatic boundary condition and is in a zone with a multiplier of 1. Adding #{length_ip_display} (ft) to perimeter length of #{story.name} for this surface, assuming it is a party wall.")
            else
              length = 0
            end

          else
            length = OpenStudio::Vector3d.new(point_one - point_two).length
          end

          if optional_multiplier_adjustment.nil?
            perimeter += length
          else
            # adjust for multiplier
            non_story_multiplier = space.multiplier/optional_multiplier_adjustment.to_f
            perimeter += length * non_story_multiplier
          end

        end
      end
    end

    return {:perimeter => perimeter,:party_walls => party_walls}
  end

  # currently takes in model and checks for edges shared by a ground exposed floor and exterior exposed wall. Later could be updated for a specific story independent of floor boundary condition.
  # todo - this doesn't catch walls that are split that sit above floor surfaces that are not (e.g. main corridoor in secondary school model)
  # todo - also odd with multi-height spaces
  def OsLib_Geometry.calculate_perimeter(model)

    perimeter = 0
    model.getSpaces.each do |space|
      # counter to use later
      edge_hash = {}
      edge_counter = 0
      space.surfaces.each do |surface|
        # get vertices
        vertex_hash = {}
        vertex_counter = 0
        surface.vertices.each do |vertex|
          vertex_counter += 1
          vertex_hash[vertex_counter] = [vertex.x,vertex.y,vertex.z]
        end
        # make edges
        counter = 0
        vertex_hash.each do |k,v|
          edge_counter += 1
          counter += 1
          if vertex_hash.size != counter
            edge_hash[edge_counter] = [v,vertex_hash[counter+1],surface,surface.outsideBoundaryCondition,surface.surfaceType]
          else # different code for wrap around vertex
            edge_hash[edge_counter] = [v,vertex_hash[1],surface,surface.outsideBoundaryCondition,surface.surfaceType]
          end
        end
      end

      # check edges for matches (need opposite vertices and proper boundary conditions)
      edge_hash.each do |k1,v1|
        next if v1[3] != "Ground" # skip if not ground exposed floor
        next if v1[4] != "Floor"
        edge_hash.each do |k2,v2|
          next if v2[3] != "Outdoors" # skip if not exterior exposed wall (todo - update to handle basement)
          next if v2[4] != "Wall"

          # see if edges have same geometry
          # found cases where the two lines below removed edges and resulted in lower than actual perimeter. Added new code with tolerance.
          #next if not v1[0] == v2[1] # next if not same geometry reversed
          #next if not v1[1] == v2[0]

          # these are three item array's add in tollerance for each array entry
          tolerance = 0.0001
          test_a = true
          test_b = true
          3.times.each do |i|
            if (v1[0][i] - v2[1][i]).abs > tolerance
              test_a = false
            end
            if (v1[1][i] - v2[0][i]).abs > tolerance
              test_b = false
            end
          end

          next if not test_a == true
          next if not test_b == true

          point_one = OpenStudio::Point3d.new(v1[0][0],v1[0][1],v1[0][2])
          point_two = OpenStudio::Point3d.new(v1[1][0],v1[1][1],v1[1][2])
          length = OpenStudio::Vector3d.new(point_one - point_two).length
          perimeter += length
        end
      end
    end

    return perimeter
  end

end