// COPYRIGHT 2026 by the Open Rails project.
//
// This file is part of Open Rails.
//
// Open Rails is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Open Rails is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Open Rails.  If not, see <http://www.gnu.org/licenses/>.

// This file is the responsibility of the 3D & Environment Team.

////////////////////////////////////////////////////////////////////////////////
//                P O S T   P R O C E S S I N G   S H A D E R                 //
////////////////////////////////////////////////////////////////////////////////

////////////////////    G L O B A L   V A L U E S    ///////////////////////////

float2   ProjectionScale;   // Projection M11 and M22 halved: screen units per metre at a depth of 1 m
float2   ScreenSize;        // Width and height in pixels
texture  DepthTexture;      // Linear depth in metres (red channel)
texture  SceneTexture;      // Rendered scene color

sampler DepthSampler = sampler_state
{
	Texture = (DepthTexture);
	MagFilter = Point;
	MinFilter = Point;
	MipFilter = None;
	AddressU = Clamp;
	AddressV = Clamp;
};

sampler SceneSampler = sampler_state
{
	Texture = (SceneTexture);
	MagFilter = Point;
	MinFilter = Point;
	MipFilter = None;
	AddressU = Clamp;
	AddressV = Clamp;
};

////////////////////    V E R T E X   S H A D E R S    /////////////////////////

struct VERTEX_INPUT
{
	float4 Position  : POSITION;
	float2 TexCoords : TEXCOORD0;
};

struct VERTEX_OUTPUT
{
	float4 Position  : POSITION;
	float2 TexCoords : TEXCOORD0;
};

// Full-screen quad: positions are already in clip space.
VERTEX_OUTPUT VSFullScreen(in VERTEX_INPUT In)
{
	VERTEX_OUTPUT Out;
	Out.Position = In.Position;
	Out.TexCoords = In.TexCoords;
	return Out;
}

////////////////////    P I X E L   S H A D E R S    ///////////////////////////

// Screen-space ambient occlusion from depth only, comparing the depth of nearby samples within a world-space radius.
// Based on Mittring, "Finding Next Gen - CryEngine 2", SIGGRAPH 2007 course notes, with a range check
// to avoid darkening from distant geometry.
static const int AOSampleCount = 12;
static const float AORadiusM = 0.6;
static const float AOBiasM = 0.03;
static const float AOStrength = 0.8;
static const float AOMaxDistanceM = 150;
static const float GoldenAngleRad = 2.39996323;

float4 PSAmbientOcclusion(in VERTEX_OUTPUT In) : COLOR0
{
	float depthM = tex2D(DepthSampler, In.TexCoords).r;
	if (depthM >= AOMaxDistanceM)
		return 1;

	// Rotate the sample pattern per pixel (4x4 interleaved) to trade banding for fine noise.
	float2 pixel = floor(In.TexCoords * ScreenSize);
	float rotationRad = (fmod(pixel.x, 4) * 4 + fmod(pixel.y, 4)) * (6.2831853 / 16);
	float2 radiusUV = ProjectionScale * AORadiusM / depthM;

	float occlusion = 0;
	[unroll]
	for (int i = 0; i < AOSampleCount; i++)
	{
		// Spiral (Vogel disk) sample pattern: https://en.wikipedia.org/wiki/Fermat%27s_spiral
		float sampleRadius = sqrt((i + 0.5) / AOSampleCount);
		float angleRad = i * GoldenAngleRad + rotationRad;
		float2 offset = float2(cos(angleRad), sin(angleRad)) * sampleRadius * radiusUV;
		float sampleDepthM = tex2D(DepthSampler, In.TexCoords + offset).r;
		float differenceM = depthM - sampleDepthM;
		occlusion += step(AOBiasM, differenceM) * saturate(AORadiusM / differenceM);
	}

	float ao = 1 - AOStrength * occlusion / AOSampleCount * saturate(1 - depthM / AOMaxDistanceM);
	return float4(ao, ao, ao, 1);
}

// Mild color grading: an S-shaped contrast curve, a small saturation boost and a subtle vignette.
static const float GradeContrast = 0.2;
static const float GradeSaturation = 1.1;
static const float VignetteStrength = 0.25;
static const float3 LumCoeff = float3(0.2125, 0.7154, 0.0721);

float4 PSPostProcess(in VERTEX_OUTPUT In) : COLOR0
{
	float3 color = tex2D(SceneSampler, In.TexCoords).rgb;

	// S-curve contrast using the smoothstep polynomial 3x^2 - 2x^3: https://en.wikipedia.org/wiki/Smoothstep
	color = lerp(color, color * color * (3 - 2 * color), GradeContrast);

	float luminance = dot(color, LumCoeff);
	color = lerp(luminance, color, GradeSaturation);

	float2 fromCenter = In.TexCoords - 0.5;
	color *= 1 - VignetteStrength * dot(fromCenter, fromCenter);

	return float4(saturate(color), 1);
}

////////////////////    T E C H N I Q U E S    /////////////////////////////////

technique AmbientOcclusion {
	pass Pass_0 {
		VertexShader = compile vs_4_0_level_9_3 VSFullScreen();
		PixelShader = compile ps_4_0_level_9_3 PSAmbientOcclusion();
	}
}

technique PostProcess {
	pass Pass_0 {
		VertexShader = compile vs_4_0_level_9_3 VSFullScreen();
		PixelShader = compile ps_4_0_level_9_3 PSPostProcess();
	}
}
