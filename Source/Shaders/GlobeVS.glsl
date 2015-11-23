#ifdef COMPRESSION_BITS12
attribute vec4 compressed;
#else
attribute vec4 position3DAndHeight;
attribute vec3 textureCoordAndEncodedNormals;
#endif

uniform vec3 u_center3D;
uniform mat4 u_modifiedModelView;
uniform vec4 u_tileRectangle;

// Uniforms for 2D Mercator projection
uniform vec2 u_southAndNorthLatitude;
uniform vec2 u_southMercatorYAndOneOverHeight;

varying vec3 v_positionMC;
varying vec3 v_positionEC;

varying vec2 v_textureCoordinates;
varying vec3 v_normalMC;
varying vec3 v_normalEC;

#ifdef FOG
varying float v_distance;
varying vec3 v_mieColor;
varying vec3 v_rayleighColor;
#endif

// These functions are generated at runtime.
vec4 getPosition(vec3 position, float height, vec2 textureCoordinates);
float get2DYPositionFraction(vec2 textureCoordinates);

vec4 getPosition3DMode(vec3 position, float height, vec2 textureCoordinates)
{
    return czm_projection * (u_modifiedModelView * vec4(position, 1.0));
}

float get2DMercatorYPositionFraction(vec2 textureCoordinates)
{
    // The width of a tile at level 11, in radians and assuming a single root tile, is
    //   2.0 * czm_pi / pow(2.0, 11.0)
    // We want to just linearly interpolate the 2D position from the texture coordinates
    // when we're at this level or higher.  The constant below is the expression
    // above evaluated and then rounded up at the 4th significant digit.
    const float maxTileWidth = 0.003068;
    float positionFraction = textureCoordinates.y;
    float southLatitude = u_southAndNorthLatitude.x;
    float northLatitude = u_southAndNorthLatitude.y;
    if (northLatitude - southLatitude > maxTileWidth)
    {
        float southMercatorY = u_southMercatorYAndOneOverHeight.x;
        float oneOverMercatorHeight = u_southMercatorYAndOneOverHeight.y;

        float currentLatitude = mix(southLatitude, northLatitude, textureCoordinates.y);
        currentLatitude = clamp(currentLatitude, -czm_webMercatorMaxLatitude, czm_webMercatorMaxLatitude);
        positionFraction = czm_latitudeToWebMercatorFraction(currentLatitude, southMercatorY, oneOverMercatorHeight);
    }    
    return positionFraction;
}

float get2DGeographicYPositionFraction(vec2 textureCoordinates)
{
    return textureCoordinates.y;
}

vec4 getPositionPlanarEarth(vec3 position, float height, vec2 textureCoordinates)
{
    float yPositionFraction = get2DYPositionFraction(textureCoordinates);
    vec4 rtcPosition2D = vec4(height, mix(u_tileRectangle.st, u_tileRectangle.pq, vec2(textureCoordinates.x, yPositionFraction)), 1.0);
    return czm_projection * (u_modifiedModelView * rtcPosition2D);
}

vec4 getPosition2DMode(vec3 position, float height, vec2 textureCoordinates)
{
    return getPositionPlanarEarth(position, 0.0, textureCoordinates);
}

vec4 getPositionColumbusViewMode(vec3 position, float height, vec2 textureCoordinates)
{
    return getPositionPlanarEarth(position, height, textureCoordinates);
}

vec4 getPositionMorphingMode(vec3 position, float height, vec2 textureCoordinates)
{
    // We do not do RTC while morphing, so there is potential for jitter.
    // This is unlikely to be noticeable, though.
    vec3 position3DWC = position + u_center3D;
    float yPositionFraction = get2DYPositionFraction(textureCoordinates);
    vec4 position2DWC = vec4(0.0, mix(u_tileRectangle.st, u_tileRectangle.pq, vec2(textureCoordinates.x, yPositionFraction)), 1.0);
    vec4 morphPosition = czm_columbusViewMorph(position2DWC, vec4(position3DWC, 1.0), czm_morphTime);
    return czm_modelViewProjection * morphPosition;
}

#ifdef COMPRESSION_BITS12
// TODO: remove. only use matrix.
uniform float u_minimumX;
uniform float u_maximumX;
uniform float u_minimumY;
uniform float u_maximumY;
uniform float u_minimumZ;
uniform float u_maximumZ;
uniform float u_minimumHeight;
uniform float u_maximumHeight;
uniform mat3 u_scaleAndBias;
#endif

void main() 
{
#ifdef COMPRESSION_BITS12
    vec2 xy = czm_decompressTextureCoordinates(compressed.x);
    vec2 zh = czm_decompressTextureCoordinates(compressed.y);
    vec3 position = vec3(xy, zh.x);
    float height = zh.y;
    vec2 textureCoordinates = czm_decompressTextureCoordinates(compressed.z);
    float encodedNormal = compressed.w;

    position.x = position.x * (u_maximumX - u_minimumX) + u_minimumX;
    position.y = position.y * (u_maximumY - u_minimumY) + u_minimumY;
    position.z = position.z * (u_maximumZ - u_minimumZ) + u_minimumZ;
    height = height * (u_maximumHeight - u_minimumHeight) + u_minimumHeight;

    position = u_scaleAndBias * position;
#else
    vec3 position = position3DAndHeight.xyz;
    float height = position3DAndHeight.w;
    vec2 textureCoordinates = textureCoordAndEncodedNormals.xy;
    float encodedNormal = textureCoordAndEncodedNormals.z;
#endif

    vec3 position3DWC = position + u_center3D;
    gl_Position = getPosition(position, height, textureCoordinates);

    v_textureCoordinates = textureCoordinates;

#if defined(ENABLE_VERTEX_LIGHTING)
    v_positionEC = (czm_modelView3D * vec4(position3DWC, 1.0)).xyz;
    v_positionMC = position3DWC;                                 // position in model coordinates
    v_normalMC = czm_octDecode(encodedNormal);
    v_normalEC = czm_normal3D * v_normalMC;
#elif defined(SHOW_REFLECTIVE_OCEAN) || defined(ENABLE_DAYNIGHT_SHADING)
    v_positionEC = (czm_modelView3D * vec4(position3DWC, 1.0)).xyz;
    v_positionMC = position3DWC;                                 // position in model coordinates
#endif
    
#ifdef FOG
    AtmosphereColor atmosColor = computeGroundAtmosphereFromSpace(position3DWC);
    v_mieColor = atmosColor.mie;
    v_rayleighColor = atmosColor.rayleigh;
    v_distance = length((czm_modelView3D * vec4(position3DWC, 1.0)).xyz);
#endif
}