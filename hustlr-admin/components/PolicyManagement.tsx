'use client';
import { useState, useEffect } from 'react';
import { FileText, Search, Filter, MoreHorizontal, Calendar, IndianRupee, AlertCircle, PauseCircle } from 'lucide-react';
import AdminApiService from '@/lib/api-service';
import { useAdminData } from '@/components/AdminContext';
import type { AdminPolicy } from '@/lib/mock-data';

export default function PolicyManagement() {
  const [policies, setPolicies] = useState<AdminPolicy[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState('ALL');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedPolicy, setSelectedPolicy] = useState<AdminPolicy | null>(null);

  const { useMockData, lastRefresh } = useAdminData();

  useEffect(() => {
    loadPolicies();
  }, [statusFilter, useMockData, lastRefresh]);

  const loadPolicies = async () => {
    setLoading(true);
    try {
      const data = await AdminApiService.getPolicies({ status: statusFilter === 'ALL' ? undefined : statusFilter });
      setPolicies(data);
      setLoading(false);
    } catch (e) {
      setLoading(false);
    }
  };

  const handleSuspendPolicy = async (policyId: string) => {
    // In a real implementation, this would call the API
    alert(`Suspend policy ${policyId} - API call would be made here`);
    setSelectedPolicy(null);
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'active': return 'green';
      case 'expired': return 'gray';
      case 'cancelled': return 'red';
      case 'suspended': return 'orange';
      default: return 'gray';
    }
  };

  const getTierColor = (tier: string) => {
    switch (tier) {
      case 'full': return 'blue';
      case 'standard': return 'green';
      case 'basic': return 'gray';
      default: return 'gray';
    }
  };

  const filteredPolicies = policies.filter(
    (policy) =>
      policy.userName.toLowerCase().includes(searchQuery.toLowerCase()) ||
      policy.id.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const formatDate = (date: Date) => {
    return new Date(date).toLocaleDateString('en-IN', {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
    });
  };

  return (
    <div className="bg-gray-800 rounded-lg p-6 border border-gray-700">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-bold text-white">Policy Management</h2>
        <div className="flex items-center gap-2">
          <div className="relative">
            <Search className="absolute left-2 top-1/2 transform -translate-y-1/2 w-4 h-4 text-gray-400" />
            <input
              type="text"
              placeholder="Search policies..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-8 pr-4 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white text-sm"
            />
          </div>
          <div className="flex items-center gap-1 bg-gray-700 rounded-lg p-1">
            {['ALL', 'active', 'expired', 'cancelled', 'suspended'].map((status) => (
              <button
                key={status}
                onClick={() => setStatusFilter(status)}
                className={`px-3 py-1 text-xs font-bold rounded ${
                  statusFilter === status
                    ? 'bg-green-500 text-white'
                    : 'text-gray-400 hover:text-white'
                }`}
              >
                {status}
              </button>
            ))}
          </div>
        </div>
      </div>

      {loading ? (
        <div className="text-center py-8">
          <FileText className="w-8 h-8 text-green-500 animate-spin mx-auto mb-2" />
          <p className="text-gray-400">Loading policies...</p>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="text-left text-gray-400 text-xs uppercase border-b border-gray-700">
                <th className="pb-3 font-medium">Policy ID</th>
                <th className="pb-3 font-medium">User</th>
                <th className="pb-3 font-medium">Tier</th>
                <th className="pb-3 font-medium">Premium</th>
                <th className="pb-3 font-medium">Status</th>
                <th className="pb-3 font-medium">Auto-Renew</th>
                <th className="pb-3 font-medium">Coverage</th>
                <th className="pb-3 font-medium">Actions</th>
              </tr>
            </thead>
            <tbody>
              {filteredPolicies.map((policy) => (
                <tr key={policy.id} className="border-b border-gray-700/50 hover:bg-gray-700/30">
                  <td className="py-3 text-sm text-gray-300">{policy.id}</td>
                  <td className="py-3">
                    <div>
                      <p className="text-sm font-medium text-white">{policy.userName}</p>
                    </div>
                  </td>
                  <td className="py-3">
                    <span
                      className={`px-2 py-1 text-xs font-bold rounded bg-${getTierColor(policy.planTier)}-500/10 text-${getTierColor(policy.planTier)}-500 border border-${getTierColor(policy.planTier)}-500`}
                    >
                      {policy.planTier.toUpperCase()}
                    </span>
                  </td>
                  <td className="py-3">
                    <div className="flex items-center gap-1">
                      <IndianRupee className="w-4 h-4 text-green-500" />
                      <span className="text-sm font-medium text-white">{policy.weeklyPremium}/wk</span>
                    </div>
                  </td>
                  <td className="py-3">
                    <span
                      className={`px-2 py-1 text-xs font-bold rounded bg-${getStatusColor(policy.status)}-500/10 text-${getStatusColor(policy.status)}-500 border border-${getStatusColor(policy.status)}-500`}
                    >
                      {policy.status}
                    </span>
                  </td>
                  <td className="py-3">
                    {policy.autoRenew ? (
                      <span className="px-2 py-1 text-xs font-bold rounded bg-green-500/10 text-green-500 border border-green-500">
                        ON
                      </span>
                    ) : (
                      <span className="px-2 py-1 text-xs font-bold rounded bg-gray-500/10 text-gray-500 border border-gray-500">
                        OFF
                      </span>
                    )}
                  </td>
                  <td className="py-3 text-sm text-gray-300">
                    {formatDate(policy.coverageStart)} - {formatDate(policy.paidUntil)}
                  </td>
                  <td className="py-3">
                    <button
                      onClick={() => setSelectedPolicy(policy)}
                      className="p-1 text-gray-400 hover:text-white"
                    >
                      <MoreHorizontal className="w-4 h-4" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {selectedPolicy && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-gray-800 rounded-lg p-6 max-w-2xl w-full mx-4 max-h-[90vh] overflow-y-auto border border-gray-700">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-bold text-white">Policy Details</h3>
              <button
                onClick={() => setSelectedPolicy(null)}
                className="p-1 text-gray-400 hover:text-white"
              >
                <MoreHorizontal className="w-5 h-5" />
              </button>
            </div>

            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-xs text-gray-400 uppercase">Policy ID</p>
                  <p className="text-sm font-medium text-white">{selectedPolicy.id}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">User</p>
                  <p className="text-sm font-medium text-white">{selectedPolicy.userName}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Plan Tier</p>
                  <p className="text-sm font-medium text-white">{selectedPolicy.planTier.toUpperCase()}</p>
                </div>
                <div>
                  <p className="text-xs text-gray-400 uppercase">Status</p>
                  <span
                    className={`px-2 py-1 text-xs font-bold rounded bg-${getStatusColor(selectedPolicy.status)}-500/10 text-${getStatusColor(selectedPolicy.status)}-500 border border-${getStatusColor(selectedPolicy.status)}-500`}
                  >
                    {selectedPolicy.status}
                  </span>
                </div>
              </div>

              <div className="pt-4 border-t border-gray-700">
                <p className="text-xs text-gray-400 uppercase mb-2">Premium Breakdown</p>
                <div className="space-y-2 bg-gray-700/50 rounded-lg p-4">
                  <div className="flex justify-between text-sm">
                    <span className="text-gray-400">Base Premium</span>
                    <span className="text-white">₹{selectedPolicy.basePremium}</span>
                  </div>
                  <div className="flex justify-between text-sm">
                    <span className="text-gray-400">Zone Adjustment</span>
                    <span className="text-white">₹{selectedPolicy.zoneAdjustment}</span>
                  </div>
                  <div className="flex justify-between text-sm">
                    <span className="text-gray-400">ISS Adjustment</span>
                    <span className="text-white">₹{selectedPolicy.issAdjustment}</span>
                  </div>
                  <div className="flex justify-between text-sm font-bold pt-2 border-t border-gray-600">
                    <span className="text-gray-400">Weekly Premium</span>
                    <span className="text-green-500">₹{selectedPolicy.weeklyPremium}</span>
                  </div>
                </div>
              </div>

              <div className="pt-4 border-t border-gray-700">
                <p className="text-xs text-gray-400 uppercase mb-2">Coverage Limits</p>
                <div className="space-y-2 bg-gray-700/50 rounded-lg p-4">
                  <div className="flex justify-between text-sm">
                    <span className="text-gray-400">Max Weekly Payout</span>
                    <span className="text-white">₹{selectedPolicy.maxWeeklyPayout}</span>
                  </div>
                  <div className="flex justify-between text-sm">
                    <span className="text-gray-400">Max Daily Payout</span>
                    <span className="text-white">₹{selectedPolicy.maxDailyPayout}</span>
                  </div>
                </div>
              </div>

              <div className="pt-4 border-t border-gray-700">
                <p className="text-xs text-gray-400 uppercase mb-2">Coverage Timeline</p>
                <div className="space-y-2 bg-gray-700/50 rounded-lg p-4">
                  <div className="flex justify-between text-sm">
                    <span className="text-gray-400">Coverage Start</span>
                    <span className="text-white flex items-center gap-1">
                      <Calendar className="w-4 h-4" />
                      {formatDate(selectedPolicy.coverageStart)}
                    </span>
                  </div>
                  <div className="flex justify-between text-sm">
                    <span className="text-gray-400">Paid Until</span>
                    <span className="text-white">{formatDate(selectedPolicy.paidUntil)}</span>
                  </div>
                  <div className="flex justify-between text-sm">
                    <span className="text-gray-400">Commitment End</span>
                    <span className="text-white">{formatDate(selectedPolicy.commitmentEnd)}</span>
                  </div>
                </div>
              </div>

              {selectedPolicy.status === 'active' && (
                <div className="pt-4 border-t border-gray-700">
                  <button
                    onClick={() => handleSuspendPolicy(selectedPolicy.id)}
                    className="w-full flex items-center justify-center gap-2 px-4 py-2 bg-orange-500 text-white rounded-lg hover:bg-orange-600"
                  >
                    <PauseCircle className="w-4 h-4" />
                    Suspend Policy
                  </button>
                </div>
              )}

              {selectedPolicy.status === 'suspended' && (
                <div className="pt-4 border-t border-gray-700">
                  <div className="flex items-center gap-2 text-orange-500 bg-orange-500/10 rounded-lg p-3">
                    <AlertCircle className="w-5 h-5" />
                    <p className="text-sm">This policy is currently suspended</p>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
