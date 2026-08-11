import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const publicErrorCodes = new Set([
  'unauthenticated',
  'company_context_required',
  'membership_not_found',
  'permission_denied',
  'invalid_input',
  'erp_user_id_mismatch',
  'role_mapping_mismatch',
  'email_already_exists',
  'server_configuration_missing',
  'company_slug_missing',
])

function publicErrorCode(error: unknown) {
  const code = error instanceof Error ? error.message : ''
  return publicErrorCodes.has(code) ? code : 'request_failed'
}

function statusFor(code: string) {
  if (code === 'unauthenticated') return 401
  if (['membership_not_found', 'permission_denied'].includes(code)) return 403
  if (code === 'email_already_exists') return 409
  if (['server_configuration_missing', 'company_slug_missing', 'request_failed'].includes(code)) {
    return 500
  }
  return 422
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ ok: false, error: 'method_not_allowed' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 405,
    })
  }

  let createdUserId: string | null = null
  let createdCompanyId: string | null = null
  let createdCompanySlug: string | null = null
  let createdLocalUserId: string | null = null
  try {
    const url = Deno.env.get('SUPABASE_URL')
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!url || !anonKey || !serviceKey) throw new Error('server_configuration_missing')
    const authHeader = req.headers.get('Authorization') ?? ''
    const callerClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: authData, error: authError } = await callerClient.auth.getUser()
    if (authError || !authData.user) throw new Error('unauthenticated')

    const body = await req.json()
    const requestedCompanyId = String(body.company_id ?? '').trim()
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(requestedCompanyId)) {
      throw new Error('company_context_required')
    }

    const admin = createClient(url, serviceKey)
    const { data: membership, error: membershipError } = await admin
      .from('company_memberships')
      .select('company_id,is_system_admin,role_code,companies!inner(slug)')
      .eq('user_id', authData.user.id)
      .eq('company_id', requestedCompanyId)
      .eq('is_active', true)
      .maybeSingle()
    if (membershipError || !membership) throw new Error('membership_not_found')
    // User creation is intentionally restricted to the tenant system
    // administrator. Role permissions in the Flutter client are not trusted
    // for this privileged Auth operation.
    if (!membership.is_system_admin) {
      throw new Error('permission_denied')
    }
    const company = Array.isArray(membership.companies)
      ? membership.companies[0]
      : membership.companies
    const companySlug = String(company?.slug ?? '').trim()
    if (!companySlug) throw new Error('company_slug_missing')
    createdCompanyId = String(membership.company_id)
    createdCompanySlug = companySlug

    const email = String(body.email ?? '').trim().toLowerCase()
    const password = String(body.password ?? '')
    const fullName = String(body.full_name ?? '').trim()
    const localUserId = String(body.local_user_id ?? '').trim()
    createdLocalUserId = localUserId || null
    const roleCode = String(body.role_code ?? 'user').trim()
    const erpUser = body.erp_user && typeof body.erp_user === 'object'
      ? { ...body.erp_user }
      : null
    if (!email.includes('@') || password.length < 8 || !localUserId || !erpUser ||
        !['admin', 'user'].includes(roleCode)) {
      throw new Error('invalid_input')
    }
    if (String(erpUser.id ?? '') !== localUserId) throw new Error('erp_user_id_mismatch')
    if (roleCode === 'admin' && membership.role_code !== 'owner') {
      throw new Error('permission_denied')
    }
    const localRoleId = String(erpUser.roleId ?? '')
    if ((roleCode === 'admin') !== (localRoleId === 'role-admin')) {
      throw new Error('role_mapping_mismatch')
    }

    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName },
    })
    if (createError || !created.user) {
      if (String(createError?.message ?? '').toLowerCase().includes('already')) {
        throw new Error('email_already_exists')
      }
      throw createError ?? new Error('request_failed')
    }
    createdUserId = created.user.id

    const now = new Date().toISOString()
    const { error: profileError } = await admin.from('profiles').upsert({
      id: createdUserId,
      full_name: fullName || email,
      is_active: true,
      updated_at: now,
    }, { onConflict: 'id' })
    if (profileError) throw profileError

    const { error: memberError } = await admin.from('company_memberships').upsert({
      company_id: membership.company_id,
      user_id: createdUserId,
      user_email: email,
      local_user_id: localUserId,
      role_code: roleCode,
      is_system_admin: roleCode === 'admin' || roleCode === 'owner',
      is_active: true,
      updated_at: now,
    }, { onConflict: 'company_id,user_id' })
    if (memberError) throw memberError

    const payload = {
      ...erpUser,
      id: localUserId,
      email,
      cloudAuthUid: createdUserId,
      authProvider: 'supabase',
      cloudEmailVerified: 1,
      passwordHash: '',
      updatedAt: now,
    }
    const { error: recordError } = await admin.from('erp_records').upsert({
      company_id: companySlug,
      entity_type: 'users',
      record_id: localUserId,
      payload,
      updated_at: now,
      deleted_at: null,
    }, { onConflict: 'company_id,entity_type,record_id' })
    if (recordError) throw recordError

    return new Response(JSON.stringify({ ok: true, user_id: createdUserId }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    if (createdUserId) {
      try {
        const cleanupUrl = Deno.env.get('SUPABASE_URL')
        const cleanupServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
        if (!cleanupUrl || !cleanupServiceKey) {
          throw new Error('cleanup_configuration_missing')
        }
        const admin = createClient(cleanupUrl, cleanupServiceKey)
        if (createdCompanySlug && createdLocalUserId) {
          const { error: recordCleanupError } = await admin
            .from('erp_records')
            .delete()
            .eq('company_id', createdCompanySlug)
            .eq('entity_type', 'users')
            .eq('record_id', createdLocalUserId)
          if (recordCleanupError) console.error('ERP record cleanup failed', recordCleanupError)
        }
        if (createdCompanyId) {
          const { error: membershipCleanupError } = await admin
            .from('company_memberships')
            .delete()
            .eq('company_id', createdCompanyId)
            .eq('user_id', createdUserId)
          if (membershipCleanupError) console.error('Membership cleanup failed', membershipCleanupError)
        }
        const { error: profileCleanupError } = await admin
          .from('profiles')
          .delete()
          .eq('id', createdUserId)
        if (profileCleanupError) console.error('Profile cleanup failed', profileCleanupError)
        const { error: authCleanupError } = await admin.auth.admin.deleteUser(createdUserId)
        if (authCleanupError) console.error('Auth cleanup failed', authCleanupError)
      } catch (cleanupError) {
        // Preserve the original failure while making orphan cleanup visible.
        console.error('admin-create-user cleanup failed', cleanupError)
      }
    }
    const code = publicErrorCode(error)
    console.error('admin-create-user failed', error)
    return new Response(JSON.stringify({ ok: false, error: code }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: statusFor(code),
    })
  }
})
