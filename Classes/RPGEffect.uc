/*
	Generic effect class.
	Used for Poison, Freeze, Null Entropy, etc...
*/
class RPGEffect extends Inventory
	config(TitanRPG)
	abstract;

//Immunity
var config array<class<Pawn> > ImmunePawnTypes;

/*
	Harmful effects can be nullified with the Magic Nullifying modifier
	and cannot affect teammates.
*/
var config bool bHarmful;

var config bool bAllowOnSelf;
var config bool bAllowOnTeammates;
var config bool bAllowOnFlagCarriers;
var config bool bAllowOnVehicles;
var config bool bAllowStacking;

//Effect
var Controller EffectCauser;
var config float Duration;
var bool bPermanent;

var float Modifier;

var config float TimerInterval;

//Audiovisual
var Sound EffectSound;
var Material EffectOverlay;
var class<xEmitter> xEmitterClass;

var class<RPGEffectMessage> EffectMessageClass;
var class<RPGStatusIcon> StatusIconClass;

//Timing
var float LastStartTime;
var float LastEffectTime;
var float EffectLimitInterval; //to avoid sounds and effects being spammed like hell

replication
{
	reliable if(Role == ROLE_Authority && bNetDirty)
		Duration, EffectCauser;
}

static function bool CanBeApplied(Pawn Other, optional Controller Causer, optional float Duration, optional float Modifier)
{
	local int i;
	local RPGPlayerReplicationInfo RPRI;
	local RPGWeaponModifier WM;
    local array<RPGArtifact> ActiveArtifacts;

	//Stacking
	if(!default.bAllowStacking && GetFor(Other) != None)
		return false;

	//Spawn Protection
	if(default.bHarmful &&
		Other.Level.TimeSeconds <= Other.SpawnTime + DeathMatch(Other.Level.Game).SpawnProtectionTime)
	{
		return false;
	}

	//Self
	if(!default.bAllowOnSelf && Causer == Other.Controller)
		return false;

	//Teammates
	if((default.bHarmful || !default.bAllowOnTeammates) && Causer != None && Causer != Other.Controller && Causer.SameTeamAs(Other.Controller))
		return false;

	//Vehicles
	if(Other.IsA('Vehicle') && Vehicle(Other).IsVehicleEmpty())
		return false;

	if(!default.bAllowOnVehicles && Other.IsA('Vehicle'))
		return false;

	//Immune pawn types
	if(class'Util'.static.InArray(Other.class, default.ImmunePawnTypes) >= 0)
		return false;

	//Flag carriers
	if(
		!default.bAllowOnFlagCarriers &&
		Other.PlayerReplicationInfo != None &&
		Other.PlayerReplicationInfo.HasFlag != None
	)
	{
		return false;
	}

	//Weapon Modifier
	WM = class'RPGWeaponModifier'.static.GetFor(Other.Weapon);
	if(WM != None && !WM.AllowEffect(default.class, Causer, Duration, Modifier))
		return false;

    //Artifacts
    ActiveArtifacts = class'RPGArtifact'.static.GetActiveArtifacts(Other);
    for(i = 0; i < ActiveArtifacts.Length; i++) {
        if(!ActiveArtifacts[i].AllowEffect(default.class, Causer, Duration, Modifier))
            return false;
    }

	//Abilities
	RPRI = class'RPGPlayerReplicationInfo'.static.GetFor(Other.Controller);
	if(RPRI != None)
	{
		for(i = 0; i < RPRI.Abilities.length; i++)
		{
			if(RPRI.Abilities[i].bAllowed)
			{
				if(!RPRI.Abilities[i].AllowEffect(default.class, Causer, Duration, Modifier))
					return false;
			}
		}
	}
    
    return true;
}

static function RPGEffect Create(Pawn Other, optional Controller Causer, optional float OverrideDuration, optional float NewModifier)
{
	local RPGEffect Effect;
	
	if(CanBeApplied(Other, Causer, OverrideDuration, NewModifier))
	{
		Effect = GetFor(Other);
		if(Effect != None)
		{
			//Update
			Effect.Stop();
			
			Effect.EffectCauser = Causer;
			
			if(OverrideDuration > 0)
				Effect.Duration = Max(Effect.Duration, OverrideDuration);
			
			if(NewModifier > Effect.Modifier)
				Effect.Modifier = NewModifier;
		}
		else
		{
			//Create
			Effect = Other.Spawn(default.class, Other);
			Effect.GiveTo(Other);
			
			if(Effect != None)
			{
				Effect.EffectCauser = Causer;
			
				if(OverrideDuration > 0.0f)
					Effect.Duration = OverrideDuration;
				
				if(NewModifier > Effect.Modifier)
					Effect.Modifier = NewModifier;
			}
		}
	}
	
	return Effect;
}

static function RemoveAll(Pawn Other)
{
	local Inventory Inv;
	local RPGEffect Effect;
	
	Inv = Other.Inventory;
	while(Inv != None)
	{
		Effect = RPGEffect(Inv);
		Inv = Inv.Inventory;
		
		if(Effect != None)
			Effect.Destroy();
	}
}

static function Remove(Pawn Other)
{
	local Inventory Inv;
	
	Inv = Other.FindInventoryType(default.class);
	if(Inv != None)
		Inv.Destroy();
}

static function RPGEffect GetFor(Pawn Other)
{
	local RPGEffect Effect;
	
	Effect = RPGEffect(Other.FindInventoryType(default.class));
	if(Effect != None && Effect.IsInState('Activated'))
		return Effect;
	else
		return None;
}

function Start()
{
	GotoState('Activated');
}

function Stop();

function DisplayEffect();

function bool ShouldDisplayEffect()
{
	return true;
}

state Activated
{
	function DisplayEffect()
	{
		local PlayerReplicationInfo CauserPRI;
		
		if(Level.TimeSeconds - LastEffectTime >= EffectLimitInterval)
		{
			if(EffectCauser != None)
				CauserPRI = EffectCauser.PlayerReplicationInfo;

			if(EffectMessageClass != None)
				Instigator.ReceiveLocalizedMessage(EffectMessageClass, 0, Instigator.PlayerReplicationInfo, CauserPRI);

			if(xEmitterClass != None)
				Instigator.Spawn(xEmitterClass, Instigator);
		}
		
		LastEffectTime = Level.TimeSeconds;
	}

	function BeginState()
	{
        local RPGPlayerReplicationInfo RPRI;
    
		if(ShouldDisplayEffect())
		{
            Instigator.PlaySound(EffectSound, SLOT_Misc, 1.0,, 768);
			
			if(EffectOverlay != None)
				class'Sync_OverlayMaterial'.static.Sync(Instigator, EffectOverlay, Duration, false);
			
			DisplayEffect();
		}
        
        if(StatusIconClass != None) {
            RPRI = class'RPGPlayerReplicationInfo'.static.GetForPRI(Instigator.PlayerReplicationInfo);
            if(RPRI != None) {
                RPRI.ClientCreateStatusIcon(StatusIconClass);
            }
        }
		
		LastStartTime = Level.TimeSeconds;
		
		if(Duration >= TimerInterval && TimerInterval > 0)
			SetTimer(TimerInterval, true);
	}
	
	function Timer()
	{
		if(ShouldDisplayEffect())
			DisplayEffect();
	}
	
	event Tick(float dt)
	{
		if(Instigator == None || Instigator.Health <= 0)
		{
			Destroy();
			return;
		}
	
		if(!bPermanent)
		{
			Duration -= dt;
			
			if(Duration <= 0)
				Destroy();
		}
	}
	
	function EndState()
	{
        local RPGPlayerReplicationInfo RPRI;
    
        if(StatusIconClass != None) {
            RPRI = class'RPGPlayerReplicationInfo'.static.GetForPRI(Instigator.PlayerReplicationInfo);
            if(RPRI != None) {
                RPRI.ClientRemoveStatusIcon(StatusIconClass);
            }
        }
    
		SetTimer(0, false);
	}
	
	function Start();
	
	function Stop()
	{
		GotoState('');
	}
}

defaultproperties
{
	bPermanent=False

	Duration=1.00
	TimerInterval=1.00
	EffectLimitInterval=0.50

	bHarmful=True
	bAllowOnSelf=True
	bAllowOnTeammates=True
	bAllowOnFlagCarriers=True
	bAllowOnVehicles=False
	bAllowStacking=True
	
	bReplicateInstigator=True
	bOnlyRelevantToOwner=True
}
