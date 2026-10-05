-- ════════════════════════════════════════════════════════════════════════════
--  prompt_pillbox_hospital — hooks/hooks_server.lua
--  Copy over (or merge into) prompt_pillbox_hospital/hooks/hooks_server.lua,
--  then restart prompt_pillbox_hospital.
--
--  rps_prompt_exstras MRI module: when the operator's scan completes, hand
--  operator + patient to rps_prompt_exstras, which builds the MRI report.
--  (Without this hook rps_prompt_exstras falls back to watching GetMriState()
--  and guesses the operator as the nearest medic.)
--
--  Pillbox docs: mri / controls → onScanComplete, server ctx { source = operator, patient }
-- ════════════════════════════════════════════════════════════════════════════
return {
    mri = {
        entries = {
            ['controls'] = {
                onScanComplete = function(ctx)
                    if GetResourceState('rps_prompt_exstras') ~= 'started' then return end
                    exports.rps_prompt_exstras:MriScanComplete(ctx.source, ctx.patient)
                end,
            },
        },
    },
}
