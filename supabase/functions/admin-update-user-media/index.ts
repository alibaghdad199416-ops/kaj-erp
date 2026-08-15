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

function validImagePayload(value: string | null) {
  if (value == null || value.trim() === '') return true
  if (value.length > 500000) return false
  if (!value.trimStart().startsWith('data:')) return true
  return /^data:image\/(png|jpe?g|webp);base64,[a-z0-9+/=\s]+$/i.test(value.trim())
}

async function hasPermission(
  caller: ReturnType<typeof createClient>,
  companyId: string,
  code: string,
) {
  const { data, error } = await caller.rpc('erp_cloud_current_user_has_permission', {
    p_company_id: companyId,
    p_permission_code: code,
  })
  if (error) throw error
  return data === true
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return reply({ ok: false, error: 'method_not_allowed' }, 405)

  try {
    const url = Deno.env.get('SUPABASE_URL')
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!url || !anonKey || !serviceKey) {
      return reply({ ok: false, error: 'server_configuration_missing' }, 500)
    }

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
    if (!companyId || !targetUserId || !localUserId) {
      return reply({ ok: false, error: 'invalid_input' }, 422)
    }
    if (avatar != null && avatar.length > 500000) {
      return reply({ ok: false, error: 'media_payload_too_large' }, 413)
    }
    if (!validImagePayload(avatar)) {
      return reply({ ok: false, error: 'invalid_media_payload' }, 422)
    }

    const admin = createClient(url, serviceKey)
    const { data: membership, error: membershipError } = await admin
      .from('company_memberships')
      .select('role_code,is_system_admin,companies!inner(slug)')
      .eq('company_id', companyId)
      .eq('user_id', authData.user.id)
      .eq('is_active', true)
      .maybeSingle()
    if (membershipError || !membership) {
      return reply({ ok: false, error: 'membership_not_found' }, 403)
    }

    const isAdministrator = membership.is_system_admin ||
      ['owner', 'admin'].includes(membership.role_code)
    if (!isAdministrator && !await hasPermission(caller, companyId, 'users.update')) {
      return reply({ ok: false, error: 'permission_denied' }, 403)
    }

    const { data: target, error: targetError } = await admin
      .from('company_memberships')
      .select('local_user_id,role_code,is_system_admin')
      .eq('company_id', companyId)
      .eq('user_id', targetUserId)
      .maybeSingle()
    if (targetError || !target) {
      return reply({ ok: false, error: 'target_membership_not_found' }, 404)
    }
    if (String(target.local_user_id ?? '') !== localUserId) {
      return reply({ ok: false, error: 'target_identity_mismatch' }, 422)
    }
    if ((target.role_code === 'owner' || target.is_system_admin) &&
        targetUserId !== authData.user.id) {
      return reply({ ok: false, error: 'permission_denied' }, 403)
    }
    if (target.role_code === 'admin' && membership.role_code !== 'owner' &&
        targetUserId !== authData.user.id) {
      return reply({ ok: false, error: 'permission_denied' }, 403)
    }

    const company = Array.isArray(membership.companies)
      ? membership.companies[0]
      : membership.companies
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

    const expectedAvatar = String(avatar ?? '').trim()
    const currentAvatar = String(record.payload?.avatarBase64 ?? '').trim()

    // User profile edits always carry the current avatar in the Flutter model.
    // Treat an identical value as a verified no-op so users.update can change
    // non-media profile fields without also needing users.image.update.
    if (currentAvatar === expectedAvatar) {
      return reply({ ok: true, action: 'update-user-media', changed: false })
    }

    if (!isAdministrator && !await hasPermission(caller, companyId, 'users.image.update')) {
      return reply({ ok: false, error: 'permission_denied' }, 403)
    }

    const payload = { ...(record.payload ?? {}) }
    if (expectedAvatar === '') delete payload.avatarBase64
    else payload.avatarBase64 = avatar
    payload.updatedAt = new Date().toISOString()

    const now = new Date().toISOString()
    const { error: saveError } = await admin
      .from('erp_records')
      .update({ payload, updated_at: now })
      .eq('company_id', companySlug)
      .eq('entity_type', 'users')
      .eq('record_id', localUserId)
    if (saveError) throw saveError

    const { data: persisted, error: persistedError } = await admin
      .from('erp_records')
      .select('payload')
      .eq('company_id', companySlug)
      .eq('entity_type', 'users')
      .eq('record_id', localUserId)
      .maybeSingle()
    if (persistedError || !persisted) {
      throw persistedError ?? new Error('media_readback_failed')
    }
    const actualAvatar = String(persisted.payload?.avatarBase64 ?? '').trim()
    if (actualAvatar !== expectedAvatar) throw new Error('media_readback_mismatch')

    return reply({ ok: true, action: 'update-user-media', changed: true })
  } catch (error) {
    console.error('admin-update-user-media failed', error)
    return reply({ ok: false, error: 'request_failed' }, 500)
  }
})
