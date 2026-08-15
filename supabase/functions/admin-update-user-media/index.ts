import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function reply(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return reply({ ok: false, error: 'method_not_allowed' }, 405)

  try {
    const url = Deno.env.get('SUPABASE_URL')
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!url || !anonKey || !serviceKey) return reply({ ok: false, error: 'server_configuration_missing' }, 500)

    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    })
    const { data: authData, error: authError } = await caller.auth.getUser()
    if (authError || !authData.user) return reply({ ok: false, error: 'unauthenticated' }, 401)

    const body = await req.json()
    const companyId = String(body.company_id ?? '').trim()
    const targetUserId = String(body.target_user_id ?? '').trim()
    const localUserId = String(body.local_user_id ?? '').trim()
    const avatar = body.avatar_base64 == null ? null : String(body.avatar_base64)
    if (!companyId || !targetUserId || !localUserId) return reply({ ok: false, error: 'invalid_input' }, 422)
    if (avatar != null && avatar.length > 500000) return reply({ ok: false, error: 'media_payload_too_large' }, 413)

    const admin = createClient(url, serviceKey)
    const { data: membership } = await admin
      .from('company_memberships')
      .select('role_code,is_system_admin,companies!inner(slug)')
      .eq('company_id', companyId)
      .eq('user_id', authData.user.id)
      .eq('is_active', true)
      .maybeSingle()
    if (!membership) return reply({ ok: false, error: 'membership_not_found' }, 403)
    if (!membership.is_system_admin && !['owner', 'admin'].includes(membership.role_code)) {
      return reply({ ok: false, error: 'permission_denied' }, 403)
    }

    const { data: target } = await admin
      .from('company_memberships')
      .select('local_user_id,role_code')
      .eq('company_id', companyId)
      .eq('user_id', targetUserId)
      .maybeSingle()
    if (!target) return reply({ ok: false, error: 'target_membership_not_found' }, 404)
    if (String(target.local_user_id ?? '') !== localUserId) {
      return reply({ ok: false, error: 'target_identity_mismatch' }, 422)
    }
    if (target.role_code === 'owner' && targetUserId !== authData.user.id) {
      return reply({ ok: false, error: 'permission_denied' }, 403)
    }

    const company = Array.isArray(membership.companies) ? membership.companies[0] : membership.companies
    const companySlug = String(company?.slug ?? '').trim()
    if (!companySlug) return reply({ ok: false, error: 'company_slug_missing' }, 500)

    const { data: record, error: recordError } = await admin
      .from('erp_records')
      .select('payload')
      .eq('company_id', companySlug)
      .eq('entity_type', 'users')
      .eq('record_id', localUserId)
      .maybeSingle()
    if (recordError || !record) return reply({ ok: false, error: 'request_failed' }, 500)

    const payload = { ...(record.payload ?? {}) }
    if (avatar == null || avatar.trim() === '') delete payload.avatarBase64
    else payload.avatarBase64 = avatar
    payload.updatedAt = new Date().toISOString()

    const { error: saveError } = await admin
      .from('erp_records')
      .update({ payload, updated_at: new Date().toISOString() })
      .eq('company_id', companySlug)
      .eq('entity_type', 'users')
      .eq('record_id', localUserId)
    if (saveError) throw saveError

    return reply({ ok: true, action: 'update-user-media' })
  } catch (error) {
    console.error('admin-update-user-media failed', error)
    return reply({ ok: false, error: 'request_failed' }, 500)
  }
})
